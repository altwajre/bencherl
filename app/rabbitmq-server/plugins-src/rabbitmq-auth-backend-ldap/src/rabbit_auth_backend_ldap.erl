%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2012 VMware, Inc.  All rights reserved.
%%

-module(rabbit_auth_backend_ldap).

%% Connect to an LDAP server for authentication and authorisation

-include_lib("eldap/include/eldap.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

-behaviour(rabbit_auth_backend).

-export([description/0]).
-export([check_user_login/2, check_vhost_access/2, check_resource_access/3]).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(state, { servers,
                 user_dn_pattern,
                 dn_lookup_attribute,
                 dn_lookup_base,
                 other_bind,
                 vhost_access_query,
                 resource_access_query,
                 tag_queries,
                 use_ssl,
                 log,
                 port }).

-record(impl, { user_dn, password }).

%%--------------------------------------------------------------------

description() ->
    [{name, <<"LDAP">>},
     {description, <<"LDAP authentication / authorisation">>}].

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------

check_user_login(Username, []) ->
    gen_server:call(?SERVER, {login, Username}, infinity);

check_user_login(Username, [{password, Password}]) ->
    gen_server:call(?SERVER, {login, Username, Password}, infinity);

check_user_login(Username, AuthProps) ->
    exit({unknown_auth_props, Username, AuthProps}).

check_vhost_access(User = #user{username = Username,
                                impl     = #impl{user_dn = UserDN}}, VHost) ->
    gen_server:call(?SERVER, {check_vhost, [{username, Username},
                                            {user_dn,  UserDN},
                                            {vhost,    VHost}], User},
                    infinity).

check_resource_access(User = #user{username = Username,
                                   impl     = #impl{user_dn = UserDN}},
                      #resource{virtual_host = VHost, kind = Type, name = Name},
                      Permission) ->
    gen_server:call(?SERVER, {check_resource, [{username,   Username},
                                               {user_dn,    UserDN},
                                               {vhost,      VHost},
                                               {resource,   Type},
                                               {name,       Name},
                                               {permission, Permission}], User},
                    infinity).

%%--------------------------------------------------------------------

evaluate({constant, Bool}, _Args, _User, _LDAP) ->
    Bool;

evaluate({for, [{Type, Value, SubQuery}|Rest]}, Args, User, LDAP) ->
    case proplists:get_value(Type, Args) of
        undefined -> {error, {args_do_not_contain, Type, Args}};
        Value     -> evaluate(SubQuery, Args, User, LDAP);
        _         -> evaluate({for, Rest}, Args, User, LDAP)
    end;

evaluate({for, []}, _Args, _User, _LDAP) ->
    {error, {for_query_incomplete}};

evaluate({exists, DNPattern}, Args, _User, LDAP) ->
    %% eldap forces us to have a filter. objectClass should always be there.
    Filter = eldap:present("objectClass"),
    object_exists(DNPattern, Filter, Args, LDAP);

evaluate({in_group, DNPattern}, Args, #user{impl = #impl{user_dn = UserDN}},
         LDAP) ->
    Filter = eldap:equalityMatch("member", UserDN),
    object_exists(DNPattern, Filter, Args, LDAP);

evaluate({match, StringQuery, REQuery}, Args, User, LDAP) ->
    case re:run(evaluate(StringQuery, Args, User, LDAP),
                evaluate(REQuery, Args, User, LDAP)) of
        {match, _} -> true;
        nomatch    -> false
    end;

evaluate({string, StringPattern}, Args, _User, _LDAP) ->
    rabbit_auth_backend_ldap_util:fill(StringPattern, Args);

evaluate({attribute, DNPattern, AttributeName}, Args, _User, LDAP) ->
    attribute(DNPattern, AttributeName, Args, LDAP);

evaluate(Q, Args, _User, _LDAP) ->
    {error, {unrecognised_query, Q, Args}}.

object_exists(DNPattern, Filter, Args, LDAP) ->
    DN = rabbit_auth_backend_ldap_util:fill(DNPattern, Args),
    case eldap:search(LDAP,
                      [{base, DN},
                       {filter, Filter},
                       {attributes, ["objectClass"]}, %% Reduce verbiage
                       {scope, eldap:baseObject()}]) of
        {ok, #eldap_search_result{entries = Entries}} ->
            length(Entries) > 0;
        {error, _} = E ->
            E
    end.

attribute(DNPattern, AttributeName, Args, LDAP) ->
    DN = rabbit_auth_backend_ldap_util:fill(DNPattern, Args),
    case eldap:search(LDAP,
                      [{base, DN},
                       {filter, eldap:present("objectClass")},
                       {attributes, [AttributeName]}]) of
        {ok, #eldap_search_result{entries = [#eldap_entry{attributes = A}]}} ->
            [Attr] = proplists:get_value(AttributeName, A),
            Attr;
        {ok, #eldap_search_result{entries = _}} ->
            false;
        {error, _} = E ->
            E
    end.

evaluate_ldap(Q, Args, User, State) ->
    with_ldap(creds(User, State),
              fun(LDAP) -> evaluate(Q, Args, User, LDAP) end, State).

%%--------------------------------------------------------------------

%% TODO - ATM we create and destroy a new LDAP connection on every
%% call. This could almost certainly be more efficient.
with_ldap(Creds, Fun, State = #state{servers = Servers,
                                     use_ssl = SSL,
                                     log     = Log,
                                     port    = Port}) ->
    Opts0 = [{ssl, SSL}, {port, Port}],
    Opts = case Log of
               true ->
                   Pre = "LDAP backend: ",
                   rabbit_log:info(Pre ++ "connecting to ~p~n", [Servers]),
                   [{log, fun(1, S, A) -> rabbit_log:warning(Pre ++ S, A);
                             (2, S, A) -> rabbit_log:info   (Pre ++ S, A)
                          end} | Opts0];
               _ ->
                   Opts0
           end,
    case eldap:open(Servers, Opts) of
        {ok, LDAP} ->
            Reply = try
                        case Creds of
                            anon ->
                                Fun(LDAP);
                            {UserDN, Password} ->
                                case eldap:simple_bind(LDAP,
                                                       UserDN, Password) of
                                    ok ->
                                        Fun(LDAP);
                                    {error, invalidCredentials} ->
                                        {refused, UserDN, []};
                                    {error, _} = E ->
                                        E
                                end
                        end
                    after
                        eldap:close(LDAP)
                    end,
            {reply, Reply, State};
        Error ->
            {reply, Error, State}
    end.

get_env(F) ->
    {ok, V} = application:get_env(F),
    V.

do_login(Username, Password, LDAP,
         State = #state{ tag_queries = TagQueries }) ->
    UserDN = username_to_dn(Username, LDAP, State),
    User = #user{username     = Username,
                 auth_backend = ?MODULE,
                 impl         = #impl{user_dn  = UserDN,
                                      password = Password}},
    TagRes = [{Tag, evaluate(Q, [{username, Username},
                                 {user_dn,  UserDN}], User, LDAP)} ||
                 {Tag, Q} <- TagQueries],
    case [E || {_, E = {error, _}} <- TagRes] of
        []      -> {ok, User#user{tags = [Tag || {Tag, true} <- TagRes]}};
        [E | _] -> E
    end.

username_to_dn(Username, _LDAP, State = #state{dn_lookup_attribute = none}) ->
    fill_user_dn_pattern(Username, State);

username_to_dn(Username, LDAP, State = #state{dn_lookup_attribute = Attr,
                                              dn_lookup_base      = Base}) ->
    Filled = fill_user_dn_pattern(Username, State),
    case eldap:search(LDAP,
                      [{base, Base},
                       {filter, eldap:equalityMatch(Attr, Filled)},
                       {attributes, ["distinguishedName"]}]) of
        {ok, #eldap_search_result{entries = [#eldap_entry{attributes = A}]}} ->
            [DN] = proplists:get_value("distinguishedName", A),
            DN;
        {ok, #eldap_search_result{entries = Entries}} ->
            rabbit_log:warning("Searching for DN for ~s, got back ~p~n",
                               [Filled, Entries]),
            Filled;
        {error, _} = E ->
            exit(E)
    end.

fill_user_dn_pattern(Username, #state{user_dn_pattern = UserDNPattern}) ->
    rabbit_auth_backend_ldap_util:fill(UserDNPattern, [{username, Username}]).

creds(none, #state{other_bind = as_user}) ->
    exit(as_user_no_password);
creds(#user{impl = #impl{user_dn = UserDN, password = Password}},
      #state{other_bind = as_user}) ->
    {UserDN, Password};
creds(_, #state{other_bind = Creds}) ->
    Creds.

%%--------------------------------------------------------------------

init([]) ->
    {ok, list_to_tuple(
           [state | [get_env(F) || F <- record_info(fields, state)]])}.

handle_call({login, Username}, _From, State) ->
    %% Without password, e.g. EXTERNAL
    with_ldap(creds(none, State),
              fun(LDAP) -> do_login(Username, none, LDAP, State) end, State);

handle_call({login, Username, Password}, _From, State) ->
    with_ldap({fill_user_dn_pattern(Username, State), Password},
              fun(LDAP) -> do_login(Username, Password, LDAP, State) end,
              State);

handle_call({check_vhost, Args, User},
            _From, State = #state{vhost_access_query = Q}) ->
    evaluate_ldap(Q, Args, User, State);

handle_call({check_resource, Args, User},
            _From, State = #state{resource_access_query = Q}) ->
    evaluate_ldap(Q, Args, User, State);

handle_call(_Req, _From, State) ->
    {reply, unknown_request, State}.

handle_cast(_C, State) ->
    {noreply, State}.

handle_info(_I, State) ->
    {noreply, State}.

terminate(_, _) -> ok.

code_change(_, State, _) -> {ok, State}.

