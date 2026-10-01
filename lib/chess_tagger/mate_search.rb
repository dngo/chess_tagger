# frozen_string_literal: true

module ChessTagger
  class BudgetExceeded < StandardError; end

  # Shortest forced mate. Mate in 1 and mate in 2 consider every legal move.
  # Mate in 3 only tries checks, captures, and promotions before the mating move,
  # so a quiet three-move mate can be missed. The search stops at a node budget
  # rather than guessing.
  class MateSearch
    def initialize(position, node_limit: 40_000)
      @position = position
      @limit = node_limit
      @nodes = 0
    end

    def shortest(max_moves: 3)
      1.upto(max_moves) do |moves|
        @nodes = 0
        begin
          return moves if attacker_mates?(@position, moves, forcing: moves >= 3)
        rescue BudgetExceeded
          return nil
        end
      end
      nil
    end

    private

    def attacker_mates?(pos, moves_left, forcing:)
      tick!
      moves = ordered(pos, pos.legal_moves)
      moves.each do |move|
        next if forcing && moves_left > 1 && !forcing?(pos, move)

        pos.apply!(move)
        begin
          lost = defender_loses?(pos, moves_left - 1, forcing: forcing)
        ensure
          pos.undo!
        end
        return true if lost
      end
      false
    end

    def defender_loses?(pos, moves_left, forcing:)
      tick!
      replies = ordered(pos, pos.legal_moves)
      return pos.in_check? if replies.empty?
      return false if moves_left <= 0

      replies.each do |reply|
        pos.apply!(reply)
        begin
          lost = attacker_mates?(pos, moves_left, forcing: forcing)
        ensure
          pos.undo!
        end
        return false unless lost
      end
      true
    end

    def forcing?(pos, move)
      return true if move.promotion || move.en_passant || pos.squares[move.to]

      pos.gives_check?(move)
    end

    def ordered(pos, moves)
      enemy = pos.enemy
      moves.sort_by do |move|
        victim = pos.squares[move.to]
        victim_value = victim && pos.color_of(victim) == enemy ? pos.value(victim) : 0
        score = victim_value * 10
        score += 9 if move.promotion == "q"
        score += 4 if move.promotion
        score += 3 if move.en_passant
        -score
      end
    end

    def tick!
      @nodes += 1
      raise BudgetExceeded if @nodes > @limit
    end
  end
end
