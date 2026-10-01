# frozen_string_literal: true

require_relative "chess_tagger/version"
require_relative "chess_tagger/catalog"
require_relative "chess_tagger/move"
require_relative "chess_tagger/position"
require_relative "chess_tagger/mate_search"
require_relative "chess_tagger/mate_patterns"
require_relative "chess_tagger/scanner"
require_relative "chess_tagger/tagger"

# Tags a chess position, given as a FEN, with the tactical motifs it contains.
#
#   ChessTagger.tag("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
#   # => []
#
# Motifs are those available to the side to move: a fork already sitting on the
# board, a move that creates one, a pin, a forced mate, and so on.
module ChessTagger
  module_function

  def tag(fen)
    Tagger.new(fen).tags
  end

  def analyze(fen)
    Tagger.new(fen).analyze
  end
end
