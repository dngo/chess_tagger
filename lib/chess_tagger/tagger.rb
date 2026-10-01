# frozen_string_literal: true

module ChessTagger
  class Tagger
    def initialize(fen)
      @fen = fen.to_s.strip
      @position = Position.parse(@fen)
    end

    def tags
      ordered(found.keys)
    end

    def analyze
      {
        fen: @position.to_fen,
        side_to_move: @position.turn == "w" ? "white" : "black",
        tags: tags,
        hits: hits
      }
    end

    private

    def found
      @found ||= Scanner.new(@position).result
    end

    def hits
      tags.filter_map do |tag|
        entry = found[tag] or next

        { tag: tag, moves: entry[:moves], detail: entry[:detail] }
      end
    end

    def ordered(names)
      rank = TAGS.each_with_index.to_h
      names.sort_by { |name| rank.fetch(name, TAGS.length) }
    end
  end
end
