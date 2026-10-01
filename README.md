# Chess Tagger

A Ruby gem that reads a chess position in [FEN](https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation) and returns the tactical motifs it matches.

Tags are for the side to move. A position matches `fork` when one of that side's pieces is already forking two targets, or when a legal move creates the fork. `mate in 1` means a legal move is checkmate. The same idea covers pins, skewers, discovered attacks, removing the defender, and the other motifs below.

```ruby
require "chess_tagger"

ChessTagger.tag("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
# => ["mate in 1", "back-rank mate", "back rank", ...]

ChessTagger.analyze("4k3/8/5r2/2q5/8/8/5N2/4K3 w - - 0 1")
# => {
#      fen: "...",
#      side_to_move: "white",
#      tags: ["fork", "knight fork", "double attack", "quiet move"],
#      hits: [{ tag: "fork", moves: ["f2e4"], detail: "..." }, ...]
#    }
```

From the command line:

```bash
chess-tagger "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
```

## Install

The gem lives in this repository. From `chess_tagger/`:

```bash
bundle install
bundle exec rake test
```

Or add it to a Gemfile:

```ruby
gem "chess_tagger", path: "chess_tagger"
```

## Tags

`ChessTagger.catalog` returns every tag with a one-line definition. The set follows the usual training vocabulary (forks, pins, and skewers, plus the combinational ideas in Chess.com's tactics guide, the Chessfox motif list, and the Lichess puzzle themes):

- Mate: `mate in 1`, `mate in 2`, `mate in 3`, `checkmate`, and named patterns such as `back-rank mate`, `smothered mate`, `arabian mate`, `anastasia mate`, `boden mate`, `hook mate`, `epaulette mate`, `dovetail mate`, `swallow's tail mate`, `opera mate`, `ladder mate`, `kill box mate`
- Attack: `fork`, `pawn fork`, `knight fork`, `royal fork`, `double attack`, `pin`, `absolute pin`, `relative pin`, `skewer`, `discovered attack`, `discovered check`, `double check`, `cross-check`, `x-ray attack`, `x-ray defense`
- Combination: `deflection`, `decoy`, `attraction`, `removing the defender`, `overloading`, `interference`, `clearance`, `clearance sacrifice`, `zwischenzug`, `zwischencheck`, `undermining`, `desperado`, `sacrifice`, `queen sacrifice`, `exchange sacrifice`, `greek gift`, `demolition`, `windmill`
- Targets and structure: `trapped piece`, `domination`, `hanging piece`, `back rank`, `promotion`, `underpromotion`, `en passant`, `battery`, `alekhine's gun`, `seventh rank`, `blind swine`, `exposed king`, `attacking f2/f7`, `advanced pawn`, `passed pawn`, `connected passed pawns`, `pawn breakthrough`
- Quiet and endgame ideas: `quiet move`, `tempo`, `counter-threat`, `hit-and-run`, `stalemate`, `stalemate sacrifice`, `perpetual check`, `opposition`, `zugzwang`, `insufficient material`

## How mate search works

`mate in 1` and `mate in 2` try every legal move. `mate in 3` only tries checks, captures, and promotions before the mating move, so a quiet three-move mate can be missed. The search gives up at a node budget instead of guessing. A tag is emitted only when the mate is proved.

Zwischenzug, decoy, attraction, windmill, and perpetual check are recognized from the geometry of a short forcing try, not from a full engine evaluation. A tag means the pattern is available, not that it is the best move.
