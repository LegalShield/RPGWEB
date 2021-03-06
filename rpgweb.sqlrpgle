          ctl-opt option(*nodebugio:*srcstmt) nomain;
          /include RPGWEB/QRPGLESRC,RPGWEB_H

          dcl-proc RPGWEB_start export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
            end-pi;
            dcl-s index int(10:0) inz;
            dcl-s index2 int(10:0) inz;
            dcl-s route_found ind inz;
            dcl-ds response likeds(RPGWEBRSP) inz;
            dcl-ds request likeds(RPGWEBRQST) inz;
            dcl-s middleware_completed ind;

            RPGWEB_setup(config);

            dow 1 = 1;
              monitor;
                clear request;
                request = RPGWEB_acceptRequest(config);

                clear response;
                clear route_found;
                for index = 1 to %elem(config.routes) by 1;
                  middleware_completed = *on;

                  for index2 = 1 to %elem(config.middlewares) by 1;
                    if middleware_completed and 
                      RPGWEB_mwMatches(config.middlewares(index2) : request);
                      
                      if config.middlewares(index2).url = *blanks;
                        index2 = %elem(config.middlewares) + 1;
                        iter;
                      endif;

                      RPGWEB_mwCallback_ptr = 
                        config.middlewares(index2).procedure;
                      middleware_completed = 
                        RPGWEB_mwCallback(request : response);

                      if middleware_completed = *off;
                        index2 = %elem(config.middlewares) + 1;
                      endif;
                    endif;
                  endfor;

                  if middleware_completed = *on;
                    if RPGWEB_routeMatches(config.routes(index) : request);
                      RPGWEB_callback_ptr = config.routes(index).procedure;
                      response = RPGWEB_callback(request);
                      route_found = *on;
                      index = %elem(config.routes) + 1;
                    endif;
                  else;
                    index = %elem(config.routes) + 1;
                  endif;
                endfor;
                
                if not route_found;
                  response = RPGWEB_setResponse(request :  HTTP_NOT_FOUND);
                endif;

                RPGWEB_sendResponse(config : response);
              on-error;
                response = RPGWEB_setResponse(request :  HTTP_INTERNAL_SERVER);
              endmon;
            enddo;

            RPGWEB_stop(config);
          end-proc;



          dcl-proc RPGWEB_stop export;
            dcl-pi *n;
              config likeds(RPGWEBAPP) const;
            end-pi;

            close_port( config.return_socket_descriptor );
            close_port( config.socket_descriptor );
          end-proc;



          dcl-proc RPGWEB_acceptRequest export;
            dcl-pi *n likeds(RPGWEBRQST);
              config likeds(RPGWEBAPP);
            end-pi;
            dcl-ds socket_address likeds(socketaddr);
            dcl-s data char(32766);
            dcl-s return_code int(10:0) inz(0);

            clear socket_address;
            socket_address.sin_family = AF_INET;
            socket_address.sin_port = config.port;
            socket_address.sin_addr = INADDR_ANY;
            config.return_socket_descriptor = accept( config.socket_descriptor :
                                  %addr(socket_address) :
                                  socketaddrlen@ );
            return_code = read( config.return_socket_descriptor :
                                %addr(data) :
                                %size(data) );

            RPGWEB_translate( %len(%trim(data)) : data : 'QTCPEBC');
            return RPGWEB_parse(data);
          end-proc;



          dcl-proc RPGWEB_parse;
            dcl-pi *n likeds(RPGWEBRQST);
              raw_request varchar(32000) const;
            end-pi;
            dcl-ds request likeds(RPGWEBRQST);
            dcl-s line char(1024);
            dcl-s start int(10:0);
            dcl-s stop int(10:0);
            dcl-s position int(10:0);
            dcl-s raw_headers char(32000);
            dcl-s parts char(1024) dim(50);
            dcl-s pieces char(1024) dim(2);
            dcl-s index int(10:0);

            clear request;
            position = %scan(RPGWEB_CRLF : raw_request);
            start = 1;
            stop = position;
            line = %subst(raw_request:start:stop);

            parts = RPGWEB_split(line : ' ');
            request.method = parts(1);
            request.route = parts(2);
            request.protocol = parts(3);

            start = 0;
            start = %scan('?' : request.route);

            if start > 0;
              request.query_string =
                    RPGWEB_cleanString(%subst(request.route : start + 1));
              request.route = %subst(request.route : 1 : start - 1);
            endif;

            parts = RPGWEB_split(request.query_string : '&');
            for index = 1 to %elem(parts) by 1;
              if parts(index) <> *blanks;
                pieces = RPGWEB_split(parts(index) : '=');
                request.query_params(index).name = pieces(1);
                request.query_params(index).value = %trim(pieces(2));
              else;
                index = %elem(parts) + 1;
              endif;
            endfor;

            start = stop + 1;
            stop = %scan(RPGWEB_DBL_CRLF : raw_request);
            raw_headers = %subst(raw_request : start : stop - start);
            parts = RPGWEB_split(raw_headers : RPGWEB_CRLF);

            for index = 1 to %elem(parts) by 1;
              if parts(index) <> *blanks;
                pieces = RPGWEB_split(parts(index) : ':');
                request.headers(index).name = pieces(1);
                request.headers(index).value = %trim(pieces(2));
              else;
                index = %elem(parts) + 1;
              endif;
            endfor;

            start = stop + 1;
            request.body = RPGWEB_cleanString(%subst(raw_request : start ));

            return request;
          end-proc;
        


          dcl-proc RPGWEB_getParam export;
            dcl-pi *n varchar(1024);
              request likeds(RPGWEBRQST) const;
              param char(50) const;
            end-pi;
            dcl-s param_value varchar(1024);
            dcl-s index int(10:0);

            clear param_value;
            for index = 1 to %elem(request.params) by 1;
              if RPGWEB_toUpper(request.params(index).name) =
                RPGWEB_toUpper(param);
                param_value = request.params(index).value;
                index = %elem(request.params) + 1;
              endif;
            endfor;

            return %trim(param_value);
          end-proc;


          dcl-proc RPGWEB_getQueryParam export;
            dcl-pi *n varchar(1024);
              request likeds(RPGWEBRQST) const;
              param char(50) const;
            end-pi;
            dcl-s param_value varchar(1024);
            dcl-s index int(10:0);

            clear param_value;
            for index = 1 to %elem(request.query_params) by 1;
              if RPGWEB_toUpper(request.query_params(index).name) =
                RPGWEB_toUpper(param);
                param_value = request.query_params(index).value;
                index = %elem(request.query_params) + 1;
              endif;
            endfor;

            return %trim(param_value);
          end-proc;


          dcl-proc RPGWEB_getHeader export;
            dcl-pi *n varchar(1024);
              request likeds(RPGWEBRQST) const;
              header char(50) const;
            end-pi;
            dcl-s header_value varchar(1024);
            dcl-s index int(10:0);

            clear header_value;
            for index = 1 to %elem(request.headers) by 1;
              if RPGWEB_toUpper(request.headers(index).name) =
                RPGWEB_toUpper(header);
                header_value = request.headers(index).value;
                index = %elem(request.headers) + 1;
              endif;
            endfor;

            return %trim(header_value);
          end-proc;



          dcl-proc RPGWEB_setHeader export;
            dcl-pi *n;
              response likeds(RPGWEBRSP);
              header_name char(50) const;
              header_value varchar(1024) const;
            end-pi;
            dcl-s index int(10:0) inz;

            for index = 1 to %elem(response.headers) by 1;
              if response.headers(index).name = *blanks;
                response.headers(index).name = header_name;
                response.headers(index).value = header_value;
                index = %elem(response.headers) + 1;
              endif;
            endfor;
          end-proc;



          dcl-proc RPGWEB_routeMatches export;
            dcl-pi *n ind;
              route likeds(RPGWEB_route_ds);
              request likeds(RPGWEBRQST);
            end-pi;
            dcl-s position int(10:0);
            dcl-s url varchar(32000);
            dcl-s start int(10:0);
            dcl-s new_start int(10:0);
            dcl-s stop int(10:0);
            dcl-s quit ind inz;
            dcl-s index int(10:0);
            dcl-s route_comparison varchar(32000);

            clear request.params;
            url = request.route;
            route_comparison = route.url;

            start = 0;
            new_start = 1;
            quit = *off;
            dow not quit;
              start = %scan('{' : route_comparison);
              if start > 0;
                stop = %scan('}' : route_comparison : start);

                for index = 1 to %elem(request.params) by 1;
                  if request.params(index).name = *blanks;
                    request.params(index).name = %subst( route_comparison :
                                                        start + 1 :
                                                        stop - start - 1 );
                    stop = %scan('/' : request.route : start + 1);
                    if stop = 0;
                      request.params(index).value = %subst( request.route :
                                                            start);
                    else;
                      request.params(index).value = %subst( request.route :
                                                            start :
                                                            stop - start);
                    endif;

                    route_comparison = %scanrpl('{' + 
                              %trim(request.params(index).name) + '}' : 
                              %trim(request.params(index).value) :
                              route_comparison );
                    index = %elem(request.params) + 1;
                  endif;
                endfor;
              else;
                quit = *on;
              endif;
            enddo;

            position = 0;
            exec sql set :position = regexp_instr(:url, :route_comparison);

            return position > 0 and request.method = route.method;
          end-proc;


          dcl-proc RPGWEB_mwMatches export;
            dcl-pi *n ind;
              route likeds(RPGWEB_route_ds);
              request likeds(RPGWEBRQST);
            end-pi;
            dcl-s position int(10:0);
            dcl-s url varchar(32000);
            dcl-s start int(10:0);
            dcl-s new_start int(10:0);
            dcl-s stop int(10:0);
            dcl-s quit ind inz;
            dcl-s index int(10:0);
            dcl-s route_comparison varchar(32000);

            clear request.params;
            url = request.route;
            route_comparison = route.url;

            start = 0;
            new_start = 1;
            quit = *off;
            dow not quit;
              start = %scan('{' : route_comparison);
              if start > 0;
                stop = %scan('}' : route_comparison : start);

                for index = 1 to %elem(request.params) by 1;
                  if request.params(index).name = *blanks;
                    request.params(index).name = %subst( route_comparison :
                                                        start + 1 :
                                                        stop - start - 1 );
                    stop = %scan('/' : request.route : start + 1);
                    if stop = 0;
                      request.params(index).value = %subst( request.route :
                                                            start);
                    else;
                      request.params(index).value = %subst( request.route :
                                                            start :
                                                            stop - start);
                    endif;

                    route_comparison = %scanrpl('{' + 
                              %trim(request.params(index).name) + '}' : 
                              %trim(request.params(index).value) :
                              route_comparison );
                    index = %elem(request.params) + 1;
                  endif;
                endfor;
              else;
                quit = *on;
              endif;
            enddo;

            position = 0;
            exec sql set :position = regexp_instr(:url, :route_comparison);

            return position > 0;
          end-proc;





          dcl-proc RPGWEB_sendResponse export;
            dcl-pi *n;
              config likeds(RPGWEBAPP) const;
              response likeds(RPGWEBRSP) const;
            end-pi;
            dcl-s data char(32766);
            dcl-s return_code int(10:0) inz(0);
            dcl-s index int(10:0) inz;

            data = 'HTTP/1.1 ' + %char(response.status) + ' ' +
                  %trim(RPGWEB_getMessage(response.status)) + RPGWEB_CRLF;
            data = %trim(data) + 'Connection: close' + RPGWEB_CRLF;

            for index = 1 to %elem(response.headers) by 1;
              if response.headers(index).name <> *blanks;
                data = %trim(data) +
                              %trim(response.headers(index).name) + ': ' +
                              %trim(response.headers(index).value) + 
                              RPGWEB_CRLF;
              else;
                index = %elem(response.headers) + 1;
              endif;
            endfor;

            if %len(%trim(response.body)) > 0;
              data = %trim(data) + 'Content-Length: ' +
                    %char(%len(%trim(data) + RPGWEB_DBL_CRLF + 
                    %trim(response.body))) + RPGWEB_CRLF;

              data = %trim(data) + RPGWEB_DBL_CRLF + %trim(response.body);
            else;
              data = %trim(data) + 'Content-Length: ' +
                    %char(%len(%trim(data))) + RPGWEB_DBL_CRLF;
            endif;

            RPGWEB_translate( %len(%trim(data)) : data : 'QTCPASC');

            return_code = write( config.return_socket_descriptor :
                                %addr(data) :
                                %len(%trim(data)) );
            close_port( config.return_socket_descriptor );
          end-proc;



          dcl-proc RPGWEB_setup;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
            end-pi;
            dcl-s return_code int(10:0) inz(0);
            dcl-ds socket_address likeds(socketaddr);

            HTTP_messages(1).status = HTTP_OK;
            HTTP_messages(1).text = 'OK';
            HTTP_messages(2).status = HTTP_CREATED;
            HTTP_messages(2).text = 'Created';
            HTTP_messages(3).status = HTTP_BAD_REQUEST;
            HTTP_messages(3).text = 'Bad Request';
            HTTP_messages(4).status = HTTP_UNAUTHORIZED;
            HTTP_messages(4).text = 'Unauthorized';
            HTTP_messages(5).status = HTTP_NOT_FOUND;
            HTTP_messages(5).text = 'Not Found';
            HTTP_messages(6).status = HTTP_INTERNAL_SERVER;
            HTTP_messages(6).text = 'Internal Server Error';


            config.socket_descriptor = socket(AF_INET : SOCK_STREAM : 0);
            return_code = set_socket_options( config.socket_descriptor :
                                              SOL_SOCKET :
                                              SO_REUSEADDR :
                                              %addr(option_val) :
                                              %size(option_val) );

            clear socket_address;
            socket_address.sin_family = AF_INET;
            socket_address.sin_port = config.port;
            socket_address.sin_addr = INADDR_ANY;
            return_code = bind( config.socket_descriptor :
                                %addr(socket_address) :
                                %size(socket_address) );
            return_code = listen( config.socket_descriptor : 1 );
          end-proc;



          dcl-proc RPGWEB_setRoute export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              method char(10) const;
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;
            dcl-s index int(10:0) inz;

            for index = 1 to %elem(config.routes) by 1;
              if config.routes(index).url = *blanks;
                config.routes(index).method = method;
                config.routes(index).url = url;
                config.routes(index).procedure = procedure;
                index = %elem(config.routes) + 1;
              endif;
            endfor;
          end-proc;


          dcl-proc RPGWEB_setMiddleware export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;
            dcl-s index int(10:0) inz;

            for index = 1 to %elem(config.middlewares) by 1;
              if config.middlewares(index).url = *blanks;
                config.middlewares(index).url = url;
                config.middlewares(index).procedure = procedure;
                index = %elem(config.middlewares) + 1;
              endif;
            endfor;
          end-proc;


          dcl-proc RPGWEB_get export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;

            RPGWEB_setRoute(config: HTTP_GET : url : procedure);
          end-proc;



          dcl-proc RPGWEB_put export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;

            RPGWEB_setRoute(config: HTTP_PUT : url : procedure);
          end-proc;



          dcl-proc RPGWEB_post export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;

            RPGWEB_setRoute(config: HTTP_POST : url : procedure);
          end-proc;



          dcl-proc RPGWEB_delete export;
            dcl-pi *n;
              config likeds(RPGWEBAPP);
              url varchar(32000) const;
              procedure pointer(*proc) const;
            end-pi;

            RPGWEB_setRoute(config: HTTP_DELETE : url : procedure);
          end-proc;



          dcl-proc RPGWEB_setResponse;
            dcl-pi *n likeds(RPGWEBRSP);
              request likeds(RPGWEBRQST);
              status zoned(3:0) const;
            end-pi;
            dcl-ds response likeds(RPGWEBRSP) inz;

            clear response;
            response.status = status;
            RPGWEB_setHeader(response : 'Connection' : 'Close');
          
            return response;
          end-proc;



          dcl-proc RPGWEB_toUpper;
            dcl-pi *n varchar(32000);
              param varchar(32000) const;
            end-pi;
            dcl-s return_param varchar(32000);

            exec sql set :return_param = upper(:param);

            return return_param;
          end-proc;



          dcl-proc RPGWEB_split;
            dcl-pi *n char(1024) dim(50);
              line varchar(32000) const;
              delimiter char(1) const;
            end-pi;
            dcl-s parts char(1024) dim(50);
            dcl-s start int(10:0);
            dcl-s stop int(10:0);
            dcl-s index int(10:0);
            dcl-s length int(10:0);
            dcl-s location int(10:0);

            clear parts;
            length = %len(%trim(line));

            index = 1;
            dow index < 50;
                start = stop + 1;
                if start <= length;
                    stop = %scan(delimiter:line:start);
                    if stop = *zeros;
                        stop = %len(%trim(line)) + 1;
                    endif;
                    parts(index) =
                      RPGWEB_cleanString(%subst(line:start:stop-start));
                else;
                    index = 49;
                endif;

                index = index + 1;
            enddo;

            return parts;
          end-proc;



          dcl-proc RPGWEB_cleanString;
            dcl-pi *n varchar(32000);
              dirty_string varchar(32000) const;
            end-pi;
            dcl-s cleaned_string varchar(32000);

            cleaned_string =
              %trim(%scanrpl(RPGWEB_CR : '' : 
                        %scanrpl(RPGWEB_LF : '' : dirty_string)));
            return cleaned_string;
          end-proc;



          dcl-proc RPGWEB_getMessage;
            dcl-pi *n char(25);
              status zoned(3:0) const;
            end-pi;
            dcl-s index int(10:0);
            dcl-s message char(25) inz;

            for index = 1 to %elem(HTTP_messages) by 1;
              if HTTP_messages(index).status = status;
                message = HTTP_messages(index).text;
                index = %elem(HTTP_messages) + 1;
              endif;
            endfor;

            return %trim(message);
          end-proc;