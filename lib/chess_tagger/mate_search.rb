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

    # Every first move that forces the shortest mate, with the named patterns the
    # mate ends in. Yields (moves, first_move, patterns) as each is proved, so a
    # caller that runs out of time keeps what it already has. Returns the mate
    # length, or nil when none is proved inside the budget.
    #
    # A defender with several replies can be mated in different ways. A pattern
    # is only reported when every defence ends in it.
    def solutions(max_moves: 3)
      1.upto(max_moves) do |moves|
        @nodes = 0
        found = 0
        forcing = moves >= 3
        begin
          ordered(@position, @position.legal_moves).each do |move|
            next if forcing && moves > 1 && !forcing?(@position, move)

            patterns = proved_patterns(move, moves, forcing: forcing)
            next unless patterns

            found += 1
            yield moves, move, patterns
          end
        rescue BudgetExceeded
          return found.positive? ? moves : nil
        end
        return moves if found.positive?
      end
      nil
    end

    private

    def proved_patterns(move, moves, forcing:)
      @position.apply!(move)
      begin
        return unless defender_loses?(@position, moves - 1, forcing: forcing)

        line_patterns(@position, moves - 1, forcing: forcing)
      rescue BudgetExceeded
        []
      ensure
        @position.undo!
      end
    end

    # `pos` has the defender to move and loses within `moves_left` more attacker moves.
    def line_patterns(pos, moves_left, forcing:)
      replies = pos.legal_moves
      return MatePatterns.tags(pos, pos.enemy) if replies.empty?

      replies.map { |reply| defence_patterns(pos, reply, moves_left, forcing: forcing) }.reduce(:&)
    end

    def defence_patterns(pos, reply, moves_left, forcing:)
      pos.apply!(reply)
      begin
        mating = ordered(pos, pos.legal_moves).find do |move|
          next false if forcing && moves_left > 1 && !forcing?(pos, move)

          mates_after?(pos, move, moves_left, forcing: forcing)
        end
        return [] unless mating

        pos.apply!(mating)
        begin
          line_patterns(pos, moves_left - 1, forcing: forcing)
        ensure
          pos.undo!
        end
      ensure
        pos.undo!
      end
    end

    def mates_after?(pos, move, moves_left, forcing:)
      pos.apply!(move)
      defender_loses?(pos, moves_left - 1, forcing: forcing)
    ensure
      pos.undo!
    end

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
