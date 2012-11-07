-module(moves).

-export([bench_args/2, run/3]).

bench_args(Version, _) ->
    Tests = case Version of
                short        -> ["bebebbeeeewwwbw"];
                intermediate -> ["bebebbeeeewwwbw", "bebebeeewewewewwe"];
                long         -> ["bebebbeeeewwwbw", "bebebeeewewewewwe", "bebebeeewewbewwewe"]
            end,
    [Tests].

run(Tests, _, _) ->
    lists:foreach(
      fun (String) ->
	      io:format("Start calulating ~p ~n", [String]),
              moves_par:moves(String),
	      io:format("Stop calulating ~p ~n", [String])
      end
      , Tests).
