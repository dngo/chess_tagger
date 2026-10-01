# frozen_string_literal: true

module ChessTagger
  # Named checkmate patterns. `position` is the position in which a king is in checkmate,
  # and `mating_color` is the side that delivered it.
  module MatePatterns
    module_function

    def tags(position, mating_color)
      enemy = position.opposite(mating_color)
      king = position.king_square(enemy)
      checkers = position.attackers(king, mating_color)
      names = []
      names << "smothered mate" if smothered?(position, king, checkers, enemy)
      names << "back-rank mate" if back_rank?(position, king, checkers, enemy)
      names << "corridor mate" if corridor?(position, king, checkers)
      names << "corner mate" if corner?(position, king)
      names << "arabian mate" if arabian?(position, king, checkers, mating_color)
      names << "anastasia mate" if anastasia?(position, king, checkers, enemy, mating_color)
      names << "hook mate" if hook?(position, king, checkers, enemy, mating_color)
      names << "boden mate" if boden?(position, king, checkers, enemy, mating_color)
      names << "double bishop mate" if double_bishop?(position, king, checkers, mating_color)
      names << "epaulette mate" if epaulette?(position, king, checkers, enemy)
      names << "dovetail mate" if dovetail?(position, king, checkers, enemy)
      names << "swallow's tail mate" if swallows_tail?(position, king, checkers, enemy, mating_color)
      names << "opera mate" if opera?(position, king, checkers, enemy, mating_color)
      names << "ladder mate" if ladder?(position, king, checkers, mating_color)
      names << "kill box mate" if kill_box?(position, king, checkers, mating_color)
      names << "support mate" if support?(position, king, checkers, mating_color)
      names
    end

    def smothered?(position, king, checkers, enemy)
      return false unless checkers.size == 1 && position.kind(position.squares[checkers.first]) == "n"

      neighbors(position, king).all? { |square| own?(position, square, enemy) }
    end

    def back_rank?(position, king, checkers, enemy)
      return false unless [0, 7].include?(position.rank(king))
      return false unless checkers.any? { |square| slider?(position, square) && position.rank(square) == position.rank(king) }

      forward = position.rank(king) == 7 ? -1 : 1
      flights = neighbors(position, king).select { |square| position.rank(square) == position.rank(king) + forward }
      flights.any? && flights.all? { |square| own?(position, square, enemy) }
    end

    def corridor?(position, king, checkers)
      edge = [0, 7].include?(position.file(king))
      edge && checkers.any? { |square| slider?(position, square) && position.file(square) == position.file(king) }
    end

    def corner?(position, king)
      [[0, 0], [0, 7], [7, 0], [7, 7]].include?([position.file(king), position.rank(king)])
    end

    def arabian?(position, king, checkers, mating_color)
      return false unless corner?(position, king)

      rook = checkers.find { |square| position.kind(position.squares[square]) == "r" && adjacent?(position, square, king) }
      return false unless rook

      position.piece_squares(mating_color, ["n"]).any? do |knight|
        knight_attacks?(position, knight, rook) &&
          neighbors(position, king).any? { |flight| knight_attacks?(position, knight, flight) }
      end
    end

    def anastasia?(position, king, checkers, enemy, mating_color)
      return false unless [0, 7].include?(position.file(king))
      return false if arabian?(position, king, checkers, mating_color)
      return false unless checkers.any? { |square| slider?(position, square) }

      covered = neighbors(position, king).count do |flight|
        position.piece_squares(mating_color, ["n"]).any? { |knight| knight_attacks?(position, knight, flight) }
      end
      blocked = neighbors(position, king).count { |flight| own?(position, flight, enemy) }
      covered >= 2 && blocked >= 1
    end

    def hook?(position, king, checkers, enemy, mating_color)
      rook = checkers.find { |square| position.kind(position.squares[square]) == "r" }
      return false unless rook

      knight = position.piece_squares(mating_color, ["n"]).find { |square| knight_attacks?(position, square, rook) }
      return false unless knight
      return false unless position.piece_squares(mating_color, ["p"]).any? { |pawn| pawn_attacks?(position, pawn, knight) }

      neighbors(position, king).any? { |flight| pawn?(position, flight, enemy) }
    end

    def boden?(position, king, checkers, enemy, mating_color)
      double_bishop?(position, king, checkers, mating_color) &&
        neighbors(position, king).any? { |flight| own?(position, flight, enemy) }
    end

    def double_bishop?(position, king, checkers, mating_color)
      bishops = position.piece_squares(mating_color, ["b"])
      return false unless bishops.size >= 2

      mating = checkers.find { |square| position.kind(position.squares[square]) == "b" }
      return false unless mating

      (bishops - [mating]).any? do |bishop|
        neighbors(position, king).any? { |flight| bishop_attacks?(position, bishop, flight) }
      end
    end

    def epaulette?(position, king, checkers, enemy)
      return false unless checkers.any? { |square| slider?(position, square) }

      sides = [-1, 1].filter_map do |df|
        file = position.file(king) + df
        next unless position.on_board?(file, position.rank(king))

        position.square(file, position.rank(king))
      end
      sides.size == 2 && sides.all? { |square| own?(position, square, enemy) }
    end

    def dovetail?(position, king, checkers, enemy)
      queen = checkers.find { |square| position.kind(position.squares[square]) == "q" && diagonal_step?(position, square, king) }
      return false unless queen

      sides = [-1, 1].filter_map do |df|
        file = position.file(king) + df
        next unless position.on_board?(file, position.rank(king))

        position.square(file, position.rank(king))
      end
      sides.size == 2 && sides.all? { |square| own?(position, square, enemy) }
    end

    def swallows_tail?(position, king, checkers, enemy, mating_color)
      queen = checkers.find { |square| position.kind(position.squares[square]) == "q" && orthogonal_step?(position, square, king) }
      return false unless queen
      return false unless position.attacked_by?(queen, mating_color)
      return false if corner?(position, king)

      diagonals = [[1, 1], [1, -1], [-1, 1], [-1, -1]].filter_map do |df, dr|
        file = position.file(king) + df
        rank = position.rank(king) + dr
        next unless position.on_board?(file, rank)

        position.square(file, rank)
      end
      diagonals.count { |square| own?(position, square, enemy) } >= 2
    end

    def opera?(position, king, checkers, enemy, mating_color)
      return false unless [0, 7].include?(position.rank(king))

      rook = checkers.find { |square| position.kind(position.squares[square]) == "r" && position.rank(square) == position.rank(king) }
      return false unless rook
      return false unless position.piece_squares(mating_color, ["b"]).any? { |bishop| bishop_attacks?(position, bishop, rook) }
      return false unless neighbors(position, king).any? { |flight| own?(position, flight, enemy) }

      true
    end

    def ladder?(position, king, checkers, mating_color)
      return false unless position.piece_squares(mating_color, ["r"]).size >= 2
      return false unless checkers.any? { |square| position.kind(position.squares[square]) == "r" }

      edge = [0, 7].include?(position.rank(king)) || [0, 7].include?(position.file(king))
      edge
    end

    def kill_box?(position, king, checkers, mating_color)
      queens = position.piece_squares(mating_color, ["q"])
      rooks = position.piece_squares(mating_color, ["r"])
      return false if queens.empty? || rooks.empty?

      checker = checkers.find { |square| "qr".include?(position.kind(position.squares[square])) }
      return false unless checker

      partner = (queens + rooks - [checker]).find do |square|
        (position.rank(square) - position.rank(king)).abs == 1 ||
          (position.file(square) - position.file(king)).abs == 1
      end
      !partner.nil?
    end

    def support?(position, king, checkers, mating_color)
      checkers.any? do |square|
        adjacent?(position, square, king) && position.attacked_by?(square, mating_color)
      end
    end

    def neighbors(position, king)
      Position::KING_OFFSETS.filter_map do |df, dr|
        file = position.file(king) + df
        rank = position.rank(king) + dr
        next unless position.on_board?(file, rank)

        position.square(file, rank)
      end
    end

    def own?(position, square, color)
      piece = position.squares[square]
      piece && position.color_of(piece) == color
    end

    def pawn?(position, square, color)
      piece = position.squares[square]
      piece && position.color_of(piece) == color && position.kind(piece) == "p"
    end

    def slider?(position, square)
      "rq".include?(position.kind(position.squares[square]).to_s)
    end

    def adjacent?(position, first, second)
      (position.file(first) - position.file(second)).abs <= 1 &&
        (position.rank(first) - position.rank(second)).abs <= 1 &&
        first != second
    end

    def diagonal_step?(position, first, second)
      df = (position.file(first) - position.file(second)).abs
      dr = (position.rank(first) - position.rank(second)).abs
      df == 1 && dr == 1
    end

    def orthogonal_step?(position, first, second)
      df = (position.file(first) - position.file(second)).abs
      dr = (position.rank(first) - position.rank(second)).abs
      (df == 1 && dr.zero?) || (dr == 1 && df.zero?)
    end

    def knight_attacks?(position, from, to)
      df = (position.file(from) - position.file(to)).abs
      dr = (position.rank(from) - position.rank(to)).abs
      (df == 1 && dr == 2) || (df == 2 && dr == 1)
    end

    def bishop_attacks?(position, from, to)
      return false if from == to

      df = position.file(to) - position.file(from)
      dr = position.rank(to) - position.rank(from)
      return false unless df.abs == dr.abs && !df.zero?

      position.between?(from, to).all? { |square| position.squares[square].nil? }
    end

    def pawn_attacks?(position, from, to)
      piece = position.squares[from]
      return false unless piece && position.kind(piece) == "p"

      dir = position.white?(piece) ? 1 : -1
      (position.file(to) - position.file(from)).abs == 1 && position.rank(to) - position.rank(from) == dir
    end
  end
end
