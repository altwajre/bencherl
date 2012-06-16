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

-module(rabbit_stomp_util).

-export([parse_destination/1, parse_routing_information/1,
         parse_message_id/1, durable_subscription_queue/2]).
-export([longstr_field/2]).
-export([ack_mode/1, consumer_tag_reply_to/1, consumer_tag/1, message_headers/3,
         message_properties/1]).
-export([negotiate_version/2]).
-export([trim_headers/1]).
-export([valid_dest_prefixes/0]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stomp_frame.hrl").
-include("rabbit_stomp_prefixes.hrl").
-include("rabbit_stomp_headers.hrl").

-define(INTERNAL_TAG_PREFIX, "T_").
-define(QUEUE_TAG_PREFIX, "Q_").

%%--------------------------------------------------------------------
%% Frame and Header Parsing
%%--------------------------------------------------------------------

consumer_tag_reply_to(QueueId) ->
    internal_tag(?TEMP_QUEUE_ID_PREFIX ++ QueueId).

consumer_tag(Frame) ->
    case rabbit_stomp_frame:header(Frame, ?HEADER_ID) of
        {ok, Id} ->
            case lists:prefix(?TEMP_QUEUE_ID_PREFIX, Id) of
                false -> {ok, internal_tag(Id), "id='" ++ Id ++ "'"};
                true  -> {error, invalid_prefix}
            end;
        not_found ->
            case rabbit_stomp_frame:header(Frame, ?HEADER_DESTINATION) of
                {ok, DestHdr} ->
                    {ok, queue_tag(DestHdr),
                     "destination='" ++ DestHdr ++ "'"};
                not_found ->
                    {error, missing_destination_header}
            end
    end.

ack_mode(Frame) ->
    case rabbit_stomp_frame:header(Frame, ?HEADER_ACK, "auto") of
        "auto"              -> {auto, false};
        "client"            -> {client, true};
        "client-individual" -> {client, false}
    end.

message_properties(Frame = #stomp_frame{headers = Headers}) ->
    BinH = fun(K, V) -> rabbit_stomp_frame:binary_header(Frame, K, V) end,
    IntH = fun(K, V) -> rabbit_stomp_frame:integer_header(Frame, K, V) end,

    DeliveryMode =
        case rabbit_stomp_frame:boolean_header
                                (Frame, ?HEADER_PERSISTENT, false) of
            true  -> 2;
            false -> undefined
        end,

    #'P_basic'{
      content_type     = BinH(?HEADER_CONTENT_TYPE,     undefined),
      content_encoding = BinH(?HEADER_CONTENT_ENCODING, undefined),
      delivery_mode    = DeliveryMode,
      priority         = IntH(?HEADER_PRIORITY,         undefined),
      correlation_id   = BinH(?HEADER_CORRELATION_ID,   undefined),
      reply_to         = BinH(?HEADER_REPLY_TO,         undefined),
      message_id       = BinH(?HEADER_AMQP_MESSAGE_ID,  undefined),
      headers          = [longstr_field(K, V) ||
                             {K, V} <- Headers, user_header(K)]}.

message_headers(SessionId,
                #'basic.deliver'{consumer_tag = ConsumerTag,
                                 delivery_tag = DeliveryTag,
                                 exchange     = ExchangeBin,
                                 routing_key  = RoutingKeyBin},
                Props = #'P_basic'{headers = Headers}) ->
    Basic = [{?HEADER_DESTINATION,
              format_destination(binary_to_list(ExchangeBin),
                                 binary_to_list(RoutingKeyBin))},
             {?HEADER_MESSAGE_ID,
              create_message_id(ConsumerTag, SessionId, DeliveryTag)}],

    Standard =
        lists:foldl(
          fun({Header, Index}, Acc) ->
                  maybe_header(Header, element(Index, Props), Acc)
          end,
          case ConsumerTag of
              <<?INTERNAL_TAG_PREFIX, Id/binary>> ->
                  [{"subscription", binary_to_list(Id)} | Basic];
              _ ->
                  Basic
          end,
          [{?HEADER_CONTENT_TYPE,     #'P_basic'.content_type},
           {?HEADER_CONTENT_ENCODING, #'P_basic'.content_encoding},
           {?HEADER_PERSISTENT,       #'P_basic'.delivery_mode},
           {?HEADER_PRIORITY,         #'P_basic'.priority},
           {?HEADER_CORRELATION_ID,   #'P_basic'.correlation_id},
           {?HEADER_REPLY_TO,         #'P_basic'.reply_to},
           {?HEADER_AMQP_MESSAGE_ID,  #'P_basic'.message_id}]),

    adhoc_convert_headers(Headers, Standard).

user_header(Hdr)
  when Hdr =:= ?HEADER_CONTENT_TYPE orelse
       Hdr =:= ?HEADER_CONTENT_ENCODING orelse
       Hdr =:= ?HEADER_PERSISTENT orelse
       Hdr =:= ?HEADER_PRIORITY orelse
       Hdr =:= ?HEADER_CORRELATION_ID orelse
       Hdr =:= ?HEADER_REPLY_TO orelse
       Hdr =:= ?HEADER_AMQP_MESSAGE_ID orelse
       Hdr =:= ?HEADER_DESTINATION ->
    false;
user_header(_) ->
    true.

parse_message_id(MessageId) ->
    case split(MessageId, ?MESSAGE_ID_SEPARATOR) of
        [ConsumerTag, SessionId, DeliveryTag] ->
            {ok, {list_to_binary(ConsumerTag),
                  SessionId,
                  list_to_integer(DeliveryTag)}};
        _ ->
            {error, invalid_message_id}
    end.

negotiate_version(ClientVers, ServerVers) ->
    Common = lists:filter(fun(Ver) ->
                                  lists:member(Ver, ServerVers)
                          end, ClientVers),
    case Common of
        [] ->
            {error, no_common_version};
        [H|T] ->
            {ok, lists:foldl(fun(Ver, AccN) ->
                                max_version(Ver, AccN)
                        end, H, T)}
    end.

max_version(V, V) ->
    V;
max_version(V1, V2) ->
    Split = fun(X) -> re:split(X, "\\.", [{return, list}]) end,
    find_max_version({V1, Split(V1)}, {V2, Split(V2)}).

find_max_version({V1, [X|T1]}, {V2, [X|T2]}) ->
    find_max_version({V1, T1}, {V2, T2});
find_max_version({V1, [X]}, {V2, [Y]}) ->
    case list_to_integer(X) >= list_to_integer(Y) of
        true  -> V1;
        false -> V2
    end;
find_max_version({_V1, []}, {V2, Y}) when length(Y) > 0 ->
    V2;
find_max_version({V1, X}, {_V2, []}) when length(X) > 0 ->
    V1.

%% ---- Header processing helpers ----

longstr_field(K, V) ->
    {list_to_binary(K), longstr, list_to_binary(V)}.

maybe_header(_Key, undefined, Acc) ->
    Acc;
maybe_header(?HEADER_PERSISTENT, 2, Acc) ->
    [{?HEADER_PERSISTENT, "true"} | Acc];
maybe_header(Key, Value, Acc) when is_binary(Value) ->
    [{Key, binary_to_list(Value)} | Acc];
maybe_header(Key, Value, Acc) when is_integer(Value) ->
    [{Key, integer_to_list(Value)}| Acc];
maybe_header(_Key, _Value, Acc) ->
    Acc.

adhoc_convert_headers(undefined, Existing) ->
    Existing;
adhoc_convert_headers(Headers, Existing) ->
    lists:foldr(fun ({K, longstr, V}, Acc) ->
                        [{binary_to_list(K), binary_to_list(V)} | Acc];
                    ({K, signedint, V}, Acc) ->
                        [{binary_to_list(K), integer_to_list(V)} | Acc];
                    (_, Acc) ->
                        Acc
                end, Existing, Headers).

create_message_id(ConsumerTag, SessionId, DeliveryTag) ->
    [ConsumerTag,
     ?MESSAGE_ID_SEPARATOR,
     SessionId,
     ?MESSAGE_ID_SEPARATOR,
     integer_to_list(DeliveryTag)].

trim_headers(Frame = #stomp_frame{headers = Hdrs}) ->
    Frame#stomp_frame{headers = [{K, string:strip(V, left)} || {K, V} <- Hdrs]}.

internal_tag(Base) ->
    list_to_binary(?INTERNAL_TAG_PREFIX ++ Base).

queue_tag(Base) ->
    list_to_binary(?QUEUE_TAG_PREFIX ++ Base).

%%--------------------------------------------------------------------
%% Destination Formatting
%%--------------------------------------------------------------------

format_destination("", RoutingKey) ->
    ?QUEUE_PREFIX ++ "/" ++ escape(RoutingKey);
format_destination("amq.topic", RoutingKey) ->
    ?TOPIC_PREFIX ++ "/" ++ escape(RoutingKey);
format_destination(Exchange, "") ->
    ?EXCHANGE_PREFIX ++ "/" ++ escape(Exchange);
format_destination(Exchange, RoutingKey) ->
    ?EXCHANGE_PREFIX ++ "/" ++ escape(Exchange) ++ "/" ++ escape(RoutingKey).

%%--------------------------------------------------------------------
%% Destination Parsing
%%--------------------------------------------------------------------

parse_destination(?QUEUE_PREFIX ++ Rest) ->
    parse_simple_destination(queue, Rest);
parse_destination(?TOPIC_PREFIX ++ Rest) ->
    parse_simple_destination(topic, Rest);
parse_destination(?AMQQUEUE_PREFIX ++ Rest) ->
    parse_simple_destination(amqqueue, Rest);
parse_destination(?TEMP_QUEUE_PREFIX ++ Rest) ->
    parse_simple_destination(temp_queue, Rest);
parse_destination(?REPLY_QUEUE_PREFIX ++ Rest) ->
    %% reply queue names might have slashes
    {ok, {reply_queue, Rest}};
parse_destination(?EXCHANGE_PREFIX ++ Rest) ->
    case parse_content(Rest) of
        %% One cannot refer to the default exchange this way; it has
        %% different semantics for subscribe and send
        ["" | _]        -> {error, {invalid_destination, exchange, Rest}};
        [Name]          -> {ok, {exchange, {Name, undefined}}};
        [Name, Pattern] -> {ok, {exchange, {Name, Pattern}}};
        _               -> {error, {invalid_destination, exchange, Rest}}
    end;
parse_destination(Destination) ->
    {error, {unknown_destination, Destination}}.

parse_routing_information({exchange, {Name, undefined}}) ->
    {Name, ""};
parse_routing_information({exchange, {Name, Pattern}}) ->
    {Name, Pattern};
parse_routing_information({topic, Name}) ->
    {"amq.topic", Name};
parse_routing_information({Type, Name})
  when Type =:= queue orelse Type =:= reply_queue orelse Type =:= amqqueue ->
    {"", Name}.

valid_dest_prefixes() -> ?VALID_DEST_PREFIXES.

durable_subscription_queue(Destination, SubscriptionId) ->
    %% We need a queue name that a) can be derived from the
    %% Destination and SubscriptionId, and b) meets the constraints on
    %% AMQP queue names. It doesn't need to be secure; we use md5 here
    %% simply as a convenient means to bound the length.
    rabbit_guid:binary(
      erlang:md5(term_to_binary({Destination, SubscriptionId})),
      "stomp.dsub").

%% ---- Destination parsing helpers ----

parse_simple_destination(Type, Content) ->
    case parse_content(Content) of
        [Name = [_|_]] -> {ok, {Type, Name}};
        _              -> {error, {invalid_destination, Type, Content}}
    end.

parse_content(Content)->
    Content2 = case take_prefix("/", Content) of
                  {ok, Rest} -> Rest;
                  not_found  -> Content
               end,
    [unescape(X) || X <- split(Content2, "/")].

split([],      _Splitter) -> [];
split(Content, [])        -> Content;
split(Content, Splitter)  -> split(Content, [], [], Splitter).

split([], RPart, RParts, _Splitter) ->
    lists:reverse([lists:reverse(RPart) | RParts]);
split(Content = [Elem | Rest1], RPart, RParts, Splitter) ->
    case take_prefix(Splitter, Content) of
        {ok, Rest2} ->
            split(Rest2, [], [lists:reverse(RPart) | RParts], Splitter);
        not_found ->
            split(Rest1, [Elem | RPart], RParts, Splitter)
    end.

take_prefix([Char | Prefix], [Char | List]) -> take_prefix(Prefix, List);
take_prefix([],              List)          -> {ok, List};
take_prefix(_Prefix,         _List)         -> not_found.

unescape(Str) -> unescape(Str, []).

unescape("%2F" ++ Str, Acc) -> unescape(Str, [$/ | Acc]);
unescape([C | Str],    Acc) -> unescape(Str, [C | Acc]);
unescape([],           Acc) -> lists:reverse(Acc).

escape(Str) -> escape(Str, []).

escape([$/ | Str], Acc) -> escape(Str, "F2%" ++ Acc);  %% $/ == '2F'x
escape([$% | Str], Acc) -> escape(Str, "52%" ++ Acc);  %% $% == '25'x
escape([X | Str],  Acc) when X < 32 orelse X > 127 ->
                           escape(Str, revhex(X) ++ "%" ++ Acc);
escape([C | Str],  Acc) -> escape(Str, [C | Acc]);
escape([],         Acc) -> lists:reverse(Acc).

revhex(I) -> hexdig(I) ++ hexdig(I bsr 4).

hexdig(I) -> erlang:integer_to_list(I band 15, 16).
