# frozen_string_literal: true

module ChessTagger
  # Recognizes tactical motifs for the side to move.
  class Scanner
    PIECE_NAMES = {
      "p" => "pawn",
      "n" => "knight",
      "b" => "bishop",
      "r" => "rook",
      "q" => "queen",
      "k" => "king"
    }.freeze

    def initialize(position)
      @pos = position
      @tags = {}
    end

    def result
      scan
      @tags
    end

    private

    def scan
      if @pos.checkmate?
        add("checkmate", detail: "The side to move is checkmated")
        MatePatterns.tags(@pos, @pos.enemy).each { |tag| add(tag, detail: "Checkmate pattern on the board") }
        return
      end

      if @pos.stalemate?
        add("stalemate", detail: "No legal move and not in check")
        add("insufficient material", detail: "Not enough material to force mate") if insufficient_material?
        return
      end

      add("insufficient material", detail: "Not enough material to force mate") if insufficient_material?
      scan_static
      scan_moves
      scan_mate unless insufficient_material?
      scan_windmill
      scan_perpetual
      scan_stalemate_sacrifice
      scan_zugzwang
    end

    def scan_static
      record_line_motifs(@pos)
      record_forks(@pos)
      record_hanging
      record_overloading
      record_trapped_and_desperado
      record_structure
      record_king_safety
      record_formations
      record_opposition
    end

    def scan_moves
      us = @pos.turn
      them = @pos.enemy
      sole = sole_defenders(@pos, them)
      our_hanging = hanging_squares(@pos, us)

      @pos.legal_moves.each do |move|
        child = @pos.make(move)
        captured = captured_piece(@pos, move)
        check = child.in_check?
        revealed = revealed_targets(@pos, move, us)
        revealed.select! { |square| valuable?(child, square) || king_square?(child, square) }
        left_unsafe = piece_unsafe?(child, move.to)
        mover = @pos.squares[move.from]

        if child.checkmate?
          add("mate in 1", move: move, detail: "#{move.uci} is checkmate")
          MatePatterns.tags(child, us).each do |tag|
            add(tag, move: move, detail: "#{move.uci} is #{tag}")
          end
        end

        add("cross-check", move: move, detail: "#{move.uci} answers check with check") if @pos.in_check? && check
        add("en passant", move: move, detail: "#{move.uci} captures en passant") if move.en_passant

        if move.promotion
          add("promotion", move: move, detail: "#{move.uci} promotes")
          if move.promotion != "q" && (check || fork_targets(child, move.to).size >= 2)
            add("underpromotion", move: move, detail: "#{move.uci} underpromotes with a forcing idea")
          end
        end

        if revealed.any?
          detail = "Moving the #{name_of(mover)} uncovers an attack"
          add("discovered attack", move: move, detail: detail)
          add("clearance", move: move, detail: "The move clears a line for another piece")
          add("discovered check", move: move, detail: detail) if revealed.any? { |square| king_square?(@pos, square) }
          if left_unsafe && captured_value(captured) < @pos.value(mover)
            add("clearance sacrifice", move: move, detail: "Material is given up to open the line")
          end
        end

        add("double check", move: move, detail: "#{move.uci} checks with two pieces") if check && child.attackers(child.king_square(them), us).size >= 2

        record_forks(child, only: move.to, move: move)
        record_line_motifs(child, move: move)

        if check && back_rank_check?(child, them)
          add("back rank", move: move, detail: "#{move.uci} checks the king on the back rank")
        end

        consider_removal(move, child, sole, captured)
        consider_deflection(move, child, sole)
        consider_interference(move, child)
        consider_decoy(move, child)
        consider_sacrifice(move, child, mover, captured, left_unsafe, check, revealed)
        consider_greek_gift(move, child, check)
        consider_demolition(move, captured)
        consider_counter_threat(move, child, our_hanging, check)
        consider_hit_and_run(move, child, captured)
        consider_tempo(move, child, mover, check, revealed)
        consider_quiet(move, child, captured, check, revealed)
        consider_breakthrough(move, child)
        consider_double_attack(move, child, mover, check, revealed)
      end
    end

    def scan_mate
      return if @tags.key?("mate in 1")

      distance = MateSearch.new(@pos.dup).shortest(max_moves: 3)
      add("mate in #{distance}", detail: "Forced checkmate in #{distance}") if distance && distance > 1
    end

    def record_forks(pos, only: nil, move: nil)
      color = @pos.turn
      squares = only ? [only] : pos.piece_squares(color, %w[p n b r q k])
      squares.each do |origin|
        next unless pos.squares[origin] && pos.color_of(pos.squares[origin]) == color

        targets = fork_targets(pos, origin)
        next if targets.size < 2

        piece = pos.squares[origin]
        names = targets.map { |square| "#{name_of(pos.squares[square])} on #{algebraic(square)}" }
        detail = "#{name_of(piece).capitalize} on #{algebraic(origin)} attacks the #{names.join(' and the ')}"
        add("fork", move: move, detail: detail)
        add("double attack", move: move, detail: detail)
        add("pawn fork", move: move, detail: detail) if pos.kind(piece) == "p"
        add("knight fork", move: move, detail: detail) if pos.kind(piece) == "n"
        kinds = targets.map { |square| pos.kind(pos.squares[square]) }
        add("royal fork", move: move, detail: detail) if kinds.include?("k") && kinds.include?("q")
      end
    end

    def fork_targets(pos, origin)
      piece = pos.squares[origin]
      return [] unless piece

      pos.attacked_enemies(origin).select { |target| fork_target?(pos, piece, target) }
    end

    def fork_target?(pos, attacker, target)
      victim = pos.squares[target]
      return false unless victim
      return true if pos.kind(victim) == "k"

      attacker_kind = pos.kind(attacker)
      victim_value = pos.value(victim)
      return victim_value >= 3 if attacker_kind == "p"
      return false unless victim_value >= 3

      if attacker_kind == "k"
        return pos.attackers(target, pos.color_of(victim)).empty?
      end

      return true if victim_value > pos.value(attacker)

      pos.attackers(target, pos.color_of(victim)).empty?
    end

    def record_line_motifs(pos, move: nil, only_fronts: nil)
      line_records(pos).each do |record|
        next if only_fronts && !only_fronts.include?(record[:front])

        case record[:type]
        when "absolute pin"
          add("absolute pin", move: move, detail: record[:detail])
          add("pin", move: move, detail: record[:detail])
        when "relative pin"
          add("relative pin", move: move, detail: record[:detail])
          add("pin", move: move, detail: record[:detail])
        when "skewer"
          add("skewer", move: move, detail: record[:detail])
          add("x-ray attack", move: move, detail: record[:detail])
        when "x-ray attack"
          add("x-ray attack", move: move, detail: record[:detail])
        when "x-ray defense"
          add("x-ray defense", move: move, detail: record[:detail])
        when "battery"
          add("battery", move: move, detail: record[:detail])
        end
      end
    end

    def line_records(pos)
      color = @pos.turn
      records = []
      pos.piece_squares(color, %w[b r q]).each do |slider|
        pos.rays_from(slider).each do |ray|
          first = ray[:first]
          second = ray[:second]
          next unless second

          front = pos.squares[first]
          back = pos.squares[second]
          front_color = pos.color_of(front)
          back_color = pos.color_of(back)
          if front_color != color && back_color != color
            if pos.kind(back) == "k" && attacker_safe?(pos, slider, first)
              records << record("absolute pin", slider, first, second, "pins the #{name_of(front)} to the king")
            elsif pos.value(back) > pos.value(front) && attacker_safe?(pos, slider, first)
              records << record("relative pin", slider, first, second, "pins the #{name_of(front)} to the #{name_of(back)}")
            elsif pos.value(front) > pos.value(back) && attacker_safe?(pos, slider, first)
              records << record("skewer", slider, first, second, "skewers the #{name_of(front)} and the #{name_of(back)}")
            elsif pos.value(front) == pos.value(back) && pos.value(front) >= 3
              records << record("x-ray attack", slider, first, second, "attacks through the #{name_of(front)} toward the #{name_of(back)}")
            end
          elsif front_color == color && back_color != color && pos.value(back) >= 3
            if "brq".include?(pos.kind(front))
              records << record("battery", slider, first, second, "battery aims at the #{name_of(back)}")
            end
            records << record("x-ray attack", slider, first, second, "attacks the #{name_of(back)} through a friendly piece")
          elsif front_color != color && back_color == color && pos.value(front) >= 3 && pos.value(back) >= 3
            records << record("x-ray defense", slider, first, second, "defends the #{name_of(back)} through the #{name_of(front)}")
          end
        end
      end
      records
    end

    def record(type, slider, front, back, text)
      { type: type, front: front, back: back, slider: slider, detail: "#{algebraic(slider)} #{text}" }
    end

    def attacker_safe?(pos, slider, front)
      front_piece = pos.squares[front]
      enemy = pos.color_of(front_piece)
      can_capture = pos.attackers(slider, enemy).include?(front)
      defended = pos.attackers(slider, pos.opposite(enemy)).any?
      !(can_capture && !defended)
    end

    def record_hanging
      hanging_squares(@pos, @pos.enemy).each do |square|
        piece = @pos.squares[square]
        add("hanging piece", detail: "#{name_of(piece).capitalize} on #{algebraic(square)} is attacked and undefended")
      end
    end

    def hanging_squares(pos, color)
      pos.piece_squares(color, %w[p n b r q]).select do |square|
        pos.value(pos.squares[square]) >= 3 && hanging?(pos, square)
      end
    end

    def hanging?(pos, square)
      piece = pos.squares[square]
      return false unless piece

      color = pos.color_of(piece)
      pos.attackers(square, pos.opposite(color)).any? && pos.attackers(square, color).empty?
    end

    def piece_unsafe?(pos, square)
      piece = pos.squares[square]
      return false unless piece

      color = pos.color_of(piece)
      attackers = pos.attackers(square, pos.opposite(color))
      return false if attackers.empty?

      defenders = pos.attackers(square, color)
      return true if defenders.empty?

      cheapest = attackers.map { |origin| pos.value(pos.squares[origin]) }.min
      cheapest < pos.value(piece) && defenders.size < attackers.size
    end

    def record_overloading
      duties = Hash.new { |hash, key| hash[key] = [] }
      @pos.piece_squares(@pos.enemy, %w[p n b r q]).each do |square|
        next if @pos.attackers(square, @pos.turn).empty?

        @pos.attackers(square, @pos.enemy).each { |defender| duties[defender] << square }
      end
      duties.each do |defender, targets|
        next if targets.size < 2
        next unless targets.any? { |square| @pos.attackers(square, @pos.enemy).size == 1 }
        next unless targets.any? { |square| @pos.value(@pos.squares[square]) >= 3 }

        piece = @pos.squares[defender]
        add("overloading", detail: "#{name_of(piece).capitalize} on #{algebraic(defender)} is the sole defender of more than one attacked piece")
      end
    end

    def record_trapped_and_desperado
      record_enemy_trapped
      record_desperado
    end

    def record_enemy_trapped
      @pos.piece_squares(@pos.enemy, %w[n b r q]).each do |square|
        destinations = @pos.destinations(square)
        safe = destinations.select { |dest| flight_safe?(@pos, square, dest) }
        attacked = @pos.attackers(square, @pos.turn).any?
        winnable = attacked && (hanging?(@pos, square) || cheaper_attacker?(@pos, square))
        if destinations.empty?
          add("trapped piece", detail: "#{name_of(@pos.squares[square]).capitalize} on #{algebraic(square)} has no safe square") if winnable
          next
        end
        next unless safe.empty?

        if winnable
          add("trapped piece", detail: "#{name_of(@pos.squares[square]).capitalize} on #{algebraic(square)} has no safe square")
        elsif !attacked
          add("domination", detail: "#{name_of(@pos.squares[square]).capitalize} on #{algebraic(square)} has no legal square")
        end
      end
    end

    def record_desperado
      @pos.piece_squares(@pos.turn, %w[n b r q]).each do |square|
        next unless @pos.attackers(square, @pos.enemy).any?
        next unless @pos.destinations(square).select { |dest| flight_safe?(@pos, square, dest) }.empty?

        capture = @pos.legal_moves.find { |move| move.from == square && capture_move?(@pos, move) }
        next unless capture

        add("desperado", move: capture, detail: "#{name_of(@pos.squares[square]).capitalize} on #{algebraic(square)} is lost and can capture first")
      end
    end

    def flight_safe?(pos, origin, dest)
      color = pos.color_of(pos.squares[origin])
      attackers = pos.attackers(dest, pos.opposite(color))
      return true if attackers.empty?

      pos.attackers(dest, color).any? { |square| square != origin }
    end

    def cheaper_attacker?(pos, square)
      piece = pos.squares[square]
      pos.attackers(square, pos.opposite(pos.color_of(piece))).any? do |origin|
        pos.value(pos.squares[origin]) <= pos.value(piece)
      end
    end

    def record_structure
      color = @pos.turn
      passed = @pos.piece_squares(color, ["p"]).select { |square| passed_pawn?(@pos, square) }
      passed.each do |square|
        add("passed pawn", detail: "Passed pawn on #{algebraic(square)}")
      end
      files = passed.map { |square| @pos.file(square) }.uniq.sort
      if files.each_cons(2).any? { |left, right| right - left == 1 }
        add("connected passed pawns", detail: "Passed pawns stand on adjacent files")
      end

      @pos.piece_squares(color, ["p"]).each do |square|
        rank = @pos.rank(square)
        advanced = color == "w" ? rank >= 5 : rank <= 2
        add("advanced pawn", detail: "Advanced pawn on #{algebraic(square)}") if advanced
      end
    end

    def passed_pawn?(pos, square)
      piece = pos.squares[square]
      file = pos.file(square)
      rank = pos.rank(square)
      ahead = pos.white?(piece) ? ((rank + 1)..7) : (0...rank)
      ahead.each do |rank_index|
        [file - 1, file, file + 1].each do |file_index|
          next unless pos.on_board?(file_index, rank_index)

          other = pos.squares[pos.square(file_index, rank_index)]
          return false if other && pos.kind(other) == "p" && pos.color_of(other) != pos.color_of(piece)
        end
      end
      true
    end

    def record_king_safety
      king = @pos.king_square(@pos.enemy)
      shield = shield_squares(@pos, king)
      pawns = shield.count { |square| pawn_of?(@pos, square, @pos.enemy) }
      center = @pos.file(king).between?(2, 5) && @pos.rank(king).between?(2, 5)
      heavy = @pos.piece_squares(@pos.turn, %w[q r]).any?
      if heavy && (pawns <= 1 || center)
        add("exposed king", detail: "The enemy king on #{algebraic(king)} is exposed")
      end

      weak = @pos.enemy == "b" ? 53 : 13
      pawn = @pos.squares[weak]
      return unless pawn && @pos.kind(pawn) == "p" && @pos.color_of(pawn) == @pos.enemy
      return unless @pos.attackers(weak, @pos.turn).any?

      defenders = @pos.attackers(weak, @pos.enemy)
      return unless defenders.all? { |square| @pos.kind(@pos.squares[square]) == "k" }

      add("attacking f2/f7", detail: "#{algebraic(weak)} is attacked and defended only by the king")
    end

    def shield_squares(pos, king)
      rank = pos.rank(king)
      return [] unless [0, 1, 6, 7].include?(rank)

      direction = rank >= 6 ? -1 : 1
      file = pos.file(king)
      [file - 1, file, file + 1].filter_map do |file_index|
        rank_index = rank + direction
        next unless pos.on_board?(file_index, rank_index)

        pos.square(file_index, rank_index)
      end
    end

    def record_formations
      rooks = @pos.piece_squares(@pos.turn, ["r"])
      seventh = @pos.turn == "w" ? 6 : 1
      if rooks.count { |square| @pos.rank(square) == seventh } >= 2
        add("seventh rank", detail: "Both rooks are on the seventh rank")
        enemy_back = @pos.turn == "w" ? 7 : 0
        if @pos.rank(@pos.king_square(@pos.enemy)) == enemy_back
          add("blind swine", detail: "Rooks on the seventh rank against a king on the back rank")
        end
      end
      record_alekhine_gun
    end

    def record_alekhine_gun
      queens = @pos.piece_squares(@pos.turn, ["q"])
      rooks = @pos.piece_squares(@pos.turn, ["r"])
      return if queens.empty? || rooks.size < 2

      queens.each do |queen|
        rooks.combination(2) do |first, second|
          squares = [queen, first, second]
          same_file = squares.map { |square| @pos.file(square) }.uniq.size == 1
          same_rank = squares.map { |square| @pos.rank(square) }.uniq.size == 1
          next unless same_file || same_rank

          indexes = squares.map { |square| same_file ? @pos.rank(square) : @pos.file(square) }
          queen_index = same_file ? @pos.rank(queen) : @pos.file(queen)
          next unless queen_index == indexes.min || queen_index == indexes.max

          add("alekhine's gun", detail: "Queen and both rooks are stacked, with the queen behind")
        end
      end
    end

    def record_opposition
      return if @pos.piece_squares("w", %w[q r]).any? || @pos.piece_squares("b", %w[q r]).any?

      white_king = @pos.king_square("w")
      black_king = @pos.king_square("b")
      same_file = @pos.file(white_king) == @pos.file(black_king)
      same_rank = @pos.rank(white_king) == @pos.rank(black_king)
      return unless same_file || same_rank

      distance = same_file ? (@pos.rank(white_king) - @pos.rank(black_king)).abs : (@pos.file(white_king) - @pos.file(black_king)).abs
      return unless distance == 2
      return unless @pos.between?(white_king, black_king).all? { |square| @pos.squares[square].nil? }

      add("opposition", detail: "The kings face each other with one square between them")
    end

    def consider_removal(move, child, sole, captured)
      square = captured_square(@pos, move)
      return unless square && sole[square]

      won = sole[square].select { |target| child.squares[target] && hanging?(child, target) }
      pieces = won.select { |target| child.value(child.squares[target]) >= 3 }
      if pieces.any?
        detail = "#{move.uci} captures the defender of the #{name_of(child.squares[pieces.first])} on #{algebraic(pieces.first)}"
        add("removing the defender", move: move, detail: detail)
      end
      return unless captured && @pos.kind(captured) == "p"
      return unless won.any? { |target| child.kind(child.squares[target]) == "p" }

      add("undermining", move: move, detail: "#{move.uci} removes the pawn supporting another pawn")
    end

    def consider_deflection(move, child, sole)
      sole.each do |defender, targets|
        next if captured_square(@pos, move) == defender
        next unless child.squares[defender]
        next unless child.attackers(defender, @pos.turn).any?
        next unless hanging?(child, defender) || cheaper_attacker?(child, defender)

        threatened = targets.select { |square| child.squares[square] && child.attackers(square, @pos.turn).any? }
        next if threatened.empty?

        add("deflection", move: move, detail: "#{move.uci} attacks the defender on #{algebraic(defender)}")
      end
    end

    def consider_interference(move, child)
      return unless @pos.squares[move.to].nil?

      @pos.piece_squares(@pos.enemy, %w[b r q]).each do |slider|
        @pos.rays_from(slider).each do |ray|
          target = ray[:first]
          piece = @pos.squares[target]
          next unless piece && @pos.color_of(piece) == @pos.enemy
          next unless @pos.between?(slider, target).include?(move.to)
          next unless hanging?(child, target)
          next unless child.attackers(target, @pos.turn).any?

          add("interference", move: move, detail: "#{move.uci} blocks the line from #{algebraic(slider)} to #{algebraic(target)}")
        end
      end
    end

    def consider_decoy(move, child)
      return unless piece_unsafe?(child, move.to)

      child.attackers(move.to, @pos.enemy).each do |origin|
        reply = child.legal_moves.find { |candidate| candidate.from == origin && candidate.to == move.to }
        next unless reply

        lured = child.squares[origin]
        child.apply!(reply)
        king_lured = @pos.kind(lured) == "k"
        exploitable = fork_somewhere?(child) || skewer_somewhere?(child) || mating_reply?(child)
        exploitable ||= hanging?(child, move.to) unless king_lured
        if exploitable && king_lured
          add("attraction", move: move, detail: "#{move.uci} draws the king onto #{algebraic(move.to)}")
          add("decoy", move: move, detail: "#{move.uci} lures the king onto #{algebraic(move.to)}")
        elsif exploitable
          add("decoy", move: move, detail: "#{move.uci} lures the #{name_of(lured)} onto #{algebraic(move.to)}")
        end
        child.undo!
      end
    end

    def mating_reply?(pos)
      pos.legal_moves.any? do |candidate|
        pos.apply!(candidate)
        mate = pos.checkmate?
        pos.undo!
        mate
      end
    end

    def fork_somewhere?(pos)
      pos.piece_squares(@pos.turn, %w[p n b r q k]).any? { |square| fork_targets(pos, square).size >= 2 }
    end

    def skewer_somewhere?(pos)
      line_records(pos).any? { |record| record[:type] == "skewer" }
    end

    def consider_sacrifice(move, child, mover, captured, left_unsafe, check, revealed)
      return unless left_unsafe

      gained = captured_value(captured)
      return unless gained < @pos.value(mover)
      return unless check || revealed.any? || fork_targets(child, move.to).size >= 2 || skewer_somewhere?(child)

      add("sacrifice", move: move, detail: "#{move.uci} gives up the #{name_of(mover)}")
      add("queen sacrifice", move: move, detail: "#{move.uci} sacrifices the queen") if @pos.kind(mover) == "q"
      if @pos.kind(mover) == "r" && captured && %w[n b].include?(@pos.kind(captured))
        add("exchange sacrifice", move: move, detail: "#{move.uci} gives a rook for a minor piece")
      end
    end

    def consider_greek_gift(move, child, check)
      mover = @pos.squares[move.from]
      return unless @pos.kind(mover) == "b" && check

      if @pos.turn == "w"
        return unless move.to == 55 && @pos.king_square("b") == 62
        return unless @pos.attackers(38, "w").any? { |square| @pos.kind(@pos.squares[square]) == "n" }
      else
        return unless move.to == 15 && @pos.king_square("w") == 6
        return unless @pos.attackers(30, "b").any? { |square| @pos.kind(@pos.squares[square]) == "n" }
      end
      add("greek gift", move: move, detail: "#{move.uci} is a Greek gift bishop sacrifice")
    end

    def consider_demolition(move, captured)
      return unless captured && @pos.kind(captured) == "p"
      return if @pos.kind(@pos.squares[move.from]) == "p"
      return unless shield_squares(@pos, @pos.king_square(@pos.enemy)).include?(move.to)

      add("demolition", move: move, detail: "#{move.uci} captures a pawn in front of the king")
    end

    def consider_counter_threat(move, child, our_hanging, check)
      ignored = our_hanging.reject { |square| square == move.from }
      return if ignored.empty?

      threatens = check || child.attacked_enemies(move.to).any? do |square|
        child.value(child.squares[square]) > @pos.value(@pos.squares[ignored.first])
      end
      return unless threatens

      add("counter-threat", move: move, detail: "#{move.uci} ignores a hanging piece to create a greater threat")
    end

    def consider_hit_and_run(move, child, captured)
      return unless captured
      return unless @pos.attackers(move.from, @pos.enemy).any?
      return if piece_unsafe?(child, move.to)
      return unless @pos.value(captured) >= 3

      add("hit-and-run", move: move, detail: "#{move.uci} captures and steps out of attack")
    end

    def consider_tempo(move, child, mover, check, revealed)
      return unless check

      extra = child.attacked_enemies(move.to).any? { |square| !king_square?(child, square) } || revealed.any? { |square| !king_square?(@pos, square) }
      add("tempo", move: move, detail: "#{move.uci} checks and attacks another piece") if extra
    end

    def consider_quiet(move, child, captured, check, revealed)
      return if check || captured

      created_fork = fork_targets(child, move.to).size >= 2
      created_skewer = skewer_somewhere?(child) && line_records(@pos).none? { |record| record[:type] == "skewer" }
      return unless created_fork || created_skewer || revealed.any?

      add("quiet move", move: move, detail: "#{move.uci} neither checks nor captures, and creates a threat")
    end

    def consider_breakthrough(move, child)
      return unless @pos.kind(@pos.squares[move.from]) == "p"
      return unless passed_pawn?(child, move.to)
      return if passed_pawn?(@pos, move.from)

      add("pawn breakthrough", move: move, detail: "#{move.uci} creates a passed pawn")
    end

    def consider_double_attack(move, child, mover, check, revealed)
      other = child.attacked_enemies(move.to).reject { |square| revealed.include?(square) }
      return unless revealed.any? && (other.any? || check)

      add("double attack", move: move, detail: "#{move.uci} creates two threats at once")
    end

    def back_rank_check?(child, enemy)
      king = child.king_square(enemy)
      return false unless [0, 7].include?(child.rank(king))

      checkers = child.attackers(king, @pos.turn)
      return false unless checkers.any? { |square| "rq".include?(child.kind(child.squares[square]).to_s) && child.rank(square) == child.rank(king) }

      forward = child.rank(king) == 7 ? -1 : 1
      flights = MatePatterns.neighbors(child, king).select { |square| child.rank(square) == child.rank(king) + forward }
      flights.count { |square| child.squares[square] && child.color_of(child.squares[square]) == enemy } >= 2
    end

    def scan_windmill
      us = @pos.turn
      @pos.legal_moves.each do |move|
        next unless capture_move?(@pos, move)

        revealed = revealed_targets(@pos, move, us)
        next unless revealed.any? { |square| king_square?(@pos, square) }

        child = @pos.make(move)
        replies = child.legal_moves
        next if replies.empty?

        forced = replies.all? do |reply|
          child.apply!(reply)
            again = child.legal_moves.any? do |follow|
            enemy_king = child.king_square(@pos.enemy)
            follow.from == move.to && revealed_targets(child, follow, us).any? { |square| square == enemy_king }
          end
          child.undo!
          again
        end
        if forced
          add("windmill", move: move, detail: "#{move.uci} starts a repeating discovered check")
          break
        end
      end
    end

    def scan_perpetual
      return if @tags.key?("mate in 1") || @tags.key?("mate in 2") || @tags.key?("mate in 3")
      return unless @pos.piece_squares(@pos.turn, %w[q r]).any?

      @perpetual_nodes = 0
      add("perpetual check", detail: "Checks can be repeated against every defense") if forced_perpetual?(@pos.dup, 0, [])
    end

    def forced_perpetual?(pos, ply, seen)
      @perpetual_nodes += 1
      return false if @perpetual_nodes > 2_500 || ply > 8

      signature = pos.signature
      return true if ply >= 4 && seen.include?(signature)

      checks = pos.legal_moves.select { |move| pos.gives_check?(move) }.first(6)
      return false if checks.empty?

      checks.any? do |move|
        pos.apply!(move)
        begin
          replies = pos.legal_moves
          replies.any? && replies.all? do |reply|
            pos.apply!(reply)
            begin
              forced_perpetual?(pos, ply + 2, seen + [signature])
            ensure
              pos.undo!
            end
          end
        ensure
          pos.undo!
        end
      end
    end

    def scan_stalemate_sacrifice
      others = @pos.squares.compact.count { |piece| @pos.kind(piece) != "k" }
      return if others > 5

      @pos.legal_moves.each do |move|
        child = @pos.make(move)
        replies = child.legal_moves
        next if replies.empty?

        if replies.all? { |reply| grandchild = child.make(reply); grandchild.stalemate? }
          add("stalemate sacrifice", move: move, detail: "#{move.uci} forces stalemate")
          break
        end
      end
    end

    def scan_zugzwang
      return if @pos.in_check?
      return unless @pos.squares.compact.all? { |piece| "kp".include?(@pos.kind(piece)) }

      moves = @pos.legal_moves
      return if moves.empty? || moves.any? { |move| capture_move?(@pos, move) }

      forced = moves.all? do |move|
        child = @pos.make(move)
        child.legal_moves.any? { |reply| capture_move?(child, reply) && (child.squares[reply.to].nil? || child.kind(child.squares[reply.to]) == "p") }
      end
      add("zugzwang", detail: "Every move allows a pawn to be captured") if forced
    end

    def sole_defenders(pos, color)
      map = Hash.new { |hash, key| hash[key] = [] }
      pos.piece_squares(color, %w[p n b r q]).each do |square|
        next if pos.attackers(square, pos.opposite(color)).empty?

        defenders = pos.attackers(square, color)
        map[defenders.first] << square if defenders.size == 1
      end
      map
    end

    def revealed_targets(before, move, color)
      targets = []
      before.piece_squares(color, %w[b r q]).each do |slider|
        next if slider == move.from

        before.rays_from(slider).each do |ray|
          next unless ray[:first] == move.from && ray[:second]
          next if before.between?(slider, ray[:second]).include?(move.to)
          next unless before.squares[ray[:second]] && before.color_of(before.squares[ray[:second]]) != color

          targets << ray[:second]
        end
      end
      targets
    end

    def captured_piece(pos, move)
      return pos.squares[move.to + (pos.turn == "w" ? -8 : 8)] if move.en_passant

      pos.squares[move.to]
    end

    def captured_square(pos, move)
      return move.to + (pos.turn == "w" ? -8 : 8) if move.en_passant
      return move.to if pos.squares[move.to]

      nil
    end

    def captured_value(piece)
      piece ? @pos.value(piece) : 0
    end

    def capture_move?(pos, move)
      move.en_passant || (pos.squares[move.to] && pos.color_of(pos.squares[move.to]) != pos.turn)
    end

    def insufficient_material?
      pieces = @pos.squares.compact.reject { |piece| @pos.kind(piece) == "k" }
      return false if pieces.any? { |piece| "pqr".include?(@pos.kind(piece)) }

      knights = pieces.count { |piece| @pos.kind(piece) == "n" }
      bishop_squares = @pos.squares.each_index.select do |index|
        @pos.squares[index] && @pos.kind(@pos.squares[index]) == "b"
      end
      return false if knights >= 2 || (knights == 1 && bishop_squares.any?)
      return true if bishop_squares.empty?

      bishop_squares.map { |index| (@pos.file(index) + @pos.rank(index)).even? }.uniq.size == 1
    end

    def valuable?(pos, square)
      piece = pos.squares[square]
      piece && pos.kind(piece) != "k" && pos.value(piece) >= 3
    end

    def king_square?(pos, square)
      pos.squares[square] && pos.kind(pos.squares[square]) == "k"
    end

    def pawn_of?(pos, square, color)
      piece = pos.squares[square]
      piece && pos.kind(piece) == "p" && pos.color_of(piece) == color
    end

    def name_of(piece)
      PIECE_NAMES[piece && @pos.kind(piece)] || "piece"
    end

    def algebraic(square)
      Position.algebraic(square)
    end

    def add(tag, move: nil, detail: nil)
      entry = (@tags[tag] ||= { moves: [], detail: nil })
      entry[:detail] ||= detail
      return unless move

      uci = move.uci
      entry[:moves] << uci unless entry[:moves].include?(uci)
    end
  end
end
