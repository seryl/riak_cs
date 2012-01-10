%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2011 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(riak_moss_utils_test).

-ifdef(TEST).

-include("riak_moss.hrl").
-include_lib("eunit/include/eunit.hrl").

setup() ->
    %% Silence logging
    application:load(sasl),
    application:load(riak_moss),
    application:set_env(sasl, sasl_error_logger, {file, "riak_moss_utils_sasl.log"}),
    error_logger:tty(false),

    %% Start erlang node
    application:start(sasl),
    TestNode = list_to_atom("testnode" ++ integer_to_list(element(3, now()))),
    net_kernel:start([TestNode, shortnames]),
    application:start(lager),
    application:start(riakc),
    application:start(inets),
    application:start(mochiweb),
    application:start(webmachine),
    application:start(crypto),
    application:start(riakc),
    application:start(riak_moss).

%% TODO:
%% Implement this
teardown(_) ->
    ok.

riak_moss_utils_test_() ->
    {spawn,
     [
      {setup,
       fun setup/0,
       fun teardown/1,
       fun(_X) ->
               [
                name_matches(),
                bucket_appears(),
                key_appears(),
                content_type_sticks(),
                keys_are_sorted(),
                object_returns(),
                object_deletes(),
                nonexistent_deletes()
               ]
       end
      }]}.

%% @doc Make sure that the name
%%      of the user created is the
%%      name that makes it into
%%      the moss_user record
name_matches() ->
    Name = "fooser",
    {ok, User} = riak_moss_utils:create_user(Name),
    {"name matches test",
     fun() ->
             [
              ?_assertEqual(Name, User#moss_user.name)
             ]
     end
    }.

%% @doc Make sure that when we create
%%      a new user and one bucket for that
%%      user, that that bucket is the only
%%      one owned by that user
bucket_appears() ->
    Name = "fooser",
    BucketName = "fooser-bucket",
    {ok, User} = riak_moss_utils:create_user(Name),
    KeyID = User#moss_user.key_id,
    riak_moss_utils:create_bucket(KeyID, BucketName),
    {ok, UserAfter} = riak_moss_utils:get_user(KeyID),
    AfterBucketNames = [B#moss_bucket.name ||
                           B <- riak_moss_utils:get_buckets(UserAfter)],
    {"bucket appears test",
     fun() ->
             [
              ?_assertEqual([BucketName], AfterBucketNames)
             ]
     end
    }.

%% @doc Make sure that when we create a key
%%      that is appears in list keys for that
%%      bucket
key_appears() ->
    %% TODO:
    %% How much of a hack is it
    %% that we have to pass the
    %% key in as a list instead
    %% of a binary?
    Name = "fooser",
    BucketName = "key_appears",
    KeyName = "testkey",
    {ok, User} = riak_moss_utils:create_user(Name),
    KeyID = User#moss_user.key_id,
    ok = riak_moss_utils:create_bucket(KeyID, BucketName),
    riak_moss_utils:put_object(BucketName, KeyName,
                               "value", dict:new()),

    {ok, ListKeys} = riak_moss_utils:list_keys(BucketName),
    {"key appears test",
     fun() ->
             [
              ?_assert(lists:member(list_to_binary(KeyName), ListKeys))
             ]
     end
    }.

%% @doc Make sure that storing a doc
%%      with a content type in the metadata
%%      keeps the content-type on GET
content_type_sticks() ->
    Name = "fooser",
    BucketName = "content_type_sticks",
    KeyName = "testkey",
    CType = "x-foo/bar",
    Metadata = dict:from_list([{<<"content-type">>, CType}]),
    {ok, User} = riak_moss_utils:create_user(Name),
    KeyID = User#moss_user.key_id,
    ok = riak_moss_utils:create_bucket(KeyID, BucketName),
    riak_moss_utils:put_object(BucketName, KeyName,
                               <<"value">>, Metadata),
    {ok, Object} = riak_moss_utils:get_object(BucketName, KeyName),
    {"content type sticks test",
     fun() ->
             [
              ?_assertEqual(CType, riakc_obj:get_content_type(Object))
             ]
     end
    }.

%% TODO:
%% This would make a great
%% EQC test
keys_are_sorted() ->
    Name = "fooser",
    BucketName = "keys_are_sorted",
    Keys = [<<"dog">>, <<"zebra">>, <<"aardvark">>, <<01>>, <<"panda">>],

    {ok, User} = riak_moss_utils:create_user(Name),
    KeyID = User#moss_user.key_id,
    ok = riak_moss_utils:create_bucket(KeyID, BucketName),

    [riak_moss_utils:put_object(BucketName, binary_to_list(KeyName),
                                "value", dict:new()) ||
        KeyName <- Keys],

    {ok, ListKeys} = riak_moss_utils:list_keys(BucketName),
    {"keys are sorted test",
     fun() ->
             [
              ?_assertEqual(lists:sort(Keys), ListKeys)
             ]
     end
    }.

%% @doc Make sure that when we save an object,
%%      we can later retrieve it and get the same
%%      value
object_returns() ->
    %% TODO:
    %% it's starting to get kind of annoying
    %% that we need a KeyID to store objects
    KeyID = "0",
    BucketName = "object_returns",
    KeyName = "testkey",
    Value = <<"value">>,
    Metadata = dict:new(),

    riak_moss_utils:put_object(BucketName, KeyName,
                               Value, Metadata),

    {ok, RetrievedObject} = riak_moss_utils:get_object(BucketName, KeyName),
    {"object returns test",
     fun() ->
             [
              ?_assertEqual(Value, riakc_obj:get_value(RetrievedObject))
             ]
     end
    }.

%% @doc Make sure that after creating an
%%      object and deleting it that it
%%      no longer exists
object_deletes() ->
    KeyID = "0",
    BucketName = "object_deletes",
    KeyName = "testkey",
    Value = <<"value">>,
    Metadata = dict:new(),

    riak_moss_utils:put_object(BucketName, KeyName,
                               Value, Metadata),

    ok = riak_moss_utils:delete_object(BucketName, KeyName),
    {error, Reason} = riak_moss_utils:get_object(BucketName, KeyName),
    {"object deletes test",
     fun() ->
             [
              ?_assertEqual(Reason, notfound)
             ]
     end
    }.

%% @doc Make sure that an object
%%      that doesn't exist still
%%      deletes fine
nonexistent_deletes() ->
    Return = riak_moss_utils:delete_object("doesn't", "exist"),
    {"nonexistenet deletes test",
     fun() ->
             [
              ?_assertEqual(Return, ok)
             ]
     end
    }.

-endif.