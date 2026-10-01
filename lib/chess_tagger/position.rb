# frozen_string_literal: true

module ChessTagger
  class InvalidFen < StandardError; end

  # A chess position with legal move generation.
  # Squares are 0..63, a1 = 0, h1 = 7, a8 = 56.
  class Position
    FILES = "abcdefgh"
    RANKS = "12345678"
    STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    VALUES = { "p" => 1, "n" => 3, "b" => 3, "r" => 5, "q" => 9, "k" => 100 }.freeze
    KNIGHT_OFFSETS = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]].freeze
    KING_OFFSETS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
    BISHOP_DIRS = [[1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
    ROOK_DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
    ROOK_CASTLE = { "K" => [7, 5], "Q" => [0, 3], "k" => [63, 61], "q" => [56, 59] }.freeze

    attr_reader :squares, :turn, :castling, :ep, :halfmove, :fullmove

    def self.parse(fen)
      new(fen)
    end

    def self.algebraic(index)
      "#{FILES[index % 8]}#{RANKS[index / 8]}"
    end

    def self.parse_square(text)
      raise InvalidFen, "invalid square #{text}" unless text&.match?(/\A[a-h][1-8]\z/)

      (text[1].ord - "1".ord) * 8 + (text[0].ord - "a".ord)
    end

    def initialize(fen = STARTING_FEN)
      @undo = []
      load_fen(fen)
    end

    def initialize_copy(other)
      super
      @squares = other.squares.dup
      @undo = []
      @legal = nil
    end

    def white?(piece)
      piece && piece == piece.upcase
    end

    def color_of(piece)
      return nil unless piece

      white?(piece) ? "w" : "b"
    end

    def kind(piece)
      piece&.downcase
    end

    def value(piece)
      VALUES[kind(piece)] || 0
    end

    def opposite(color)
      color == "w" ? "b" : "w"
    end

    def enemy
      opposite(turn)
    end

    def file(index)
      index % 8
    end

    def rank(index)
      index / 8
    end

    def square(file, rank)
      rank * 8 + file
    end

    def on_board?(file, rank)
      file.between?(0, 7) && rank.between?(0, 7)
    end

    def king_square(color)
      color == "w" ? @wk : @bk
    end

    def each_piece
      squares.each_with_index do |piece, index|
        yield piece, index if piece
      end
    end

    def piece_squares(color, kinds = nil)
      found = []
      each_piece do |piece, index|
        next unless color_of(piece) == color
        next if kinds && !kinds.include?(kind(piece))

        found << index
      end
      found
    end

    def in_check?(color = turn)
      attacked_by?(king_square(color), opposite(color))
    end

    def checkmate?
      in_check? && legal_moves.empty?
    end

    def stalemate?
      !in_check? && legal_moves.empty?
    end

    def legal_moves
      return @legal if @legal

      list = []
      pseudo_legal_moves.each do |move|
        apply!(move)
        list << move unless in_check?(opposite(turn))
        undo!
      end
      @legal = list
    end

    def apply!(move)
      @undo << [@squares.dup, @turn, @castling, @ep, @halfmove, @fullmove, @wk, @bk]
      @legal = nil

      piece = squares[move.from]
      captured = squares[move.to]
      @squares[move.from] = nil
      @squares[move.to] = if move.promotion
                            white?(piece) ? move.promotion.upcase : move.promotion.downcase
                          else
                            piece
                          end

      if move.en_passant
        captured_square = move.to + (white?(piece) ? -8 : 8)
        @squares[captured_square] = nil
      end

      if move.castle
        rook_from, rook_to = ROOK_CASTLE[move.castle]
        @squares[rook_to] = @squares[rook_from]
        @squares[rook_from] = nil
      end

      @wk = move.to if piece == "K"
      @bk = move.to if piece == "k"
      update_castling(move, piece)
      update_en_passant(move, piece)
      @halfmove = (kind(piece) == "p" || captured || move.en_passant) ? 0 : @halfmove + 1
      @fullmove += 1 if @turn == "b"
      @turn = opposite(@turn)
      self
    end

    def undo!
      raise "nothing to undo" if @undo.empty?

      @squares, @turn, @castling, @ep, @halfmove, @fullmove, @wk, @bk = @undo.pop
      @legal = nil
      self
    end

    def make(move)
      copy = dup
      copy.apply!(move)
      copy
    end

    def attackers(target, color)
      found = []
      pawn_rank = color == "w" ? -1 : 1
      [-1, 1].each do |df|
        f = file(target) + df
        r = rank(target) + pawn_rank
        next unless on_board?(f, r)

        index = square(f, r)
        piece = squares[index]
        found << index if piece && kind(piece) == "p" && color_of(piece) == color
      end

      KNIGHT_OFFSETS.each do |df, dr|
        f = file(target) + df
        r = rank(target) + dr
        next unless on_board?(f, r)

        index = square(f, r)
        piece = squares[index]
        found << index if piece && kind(piece) == "n" && color_of(piece) == color
      end

      KING_OFFSETS.each do |df, dr|
        f = file(target) + df
        r = rank(target) + dr
        next unless on_board?(f, r)

        index = square(f, r)
        piece = squares[index]
        found << index if piece && kind(piece) == "k" && color_of(piece) == color
      end

      BISHOP_DIRS.each do |df, dr|
        found.concat(ray_attackers(target, df, dr, color, "bq"))
      end
      ROOK_DIRS.each do |df, dr|
        found.concat(ray_attackers(target, df, dr, color, "rq"))
      end
      found
    end

    def attacked_by?(target, color)
      !attackers(target, color).empty?
    end

    # Enemy pieces this piece attacks, one per direction for sliders.
    def attacked_enemies(origin)
      piece = squares[origin]
      return [] unless piece

      targets = []
      case kind(piece)
      when "p"
        dir = white?(piece) ? 1 : -1
        [-1, 1].each do |df|
          f = file(origin) + df
          r = rank(origin) + dir
          next unless on_board?(f, r)

          index = square(f, r)
          occupant = squares[index]
          targets << index if occupant && color_of(occupant) != color_of(piece)
        end
      when "n"
        leap_targets(origin, KNIGHT_OFFSETS, targets)
      when "k"
        leap_targets(origin, KING_OFFSETS, targets)
      when "b"
        slide_targets(origin, BISHOP_DIRS, targets)
      when "r"
        slide_targets(origin, ROOK_DIRS, targets)
      when "q"
        slide_targets(origin, BISHOP_DIRS + ROOK_DIRS, targets)
      end
      targets
    end

    # First and second pieces along each ray from a slider.
    def rays_from(origin)
      piece = squares[origin]
      return [] unless piece && "brq".include?(kind(piece))

      dirs = kind(piece) == "b" ? BISHOP_DIRS : kind(piece) == "r" ? ROOK_DIRS : BISHOP_DIRS + ROOK_DIRS
      dirs.filter_map do |df, dr|
        seen = []
        f = file(origin)
        r = rank(origin)
        loop do
          f += df
          r += dr
          break unless on_board?(f, r)

          index = square(f, r)
          next unless squares[index]

          seen << index
          break if seen.size == 2
        end
        next if seen.empty?

        { direction: [df, dr], first: seen[0], second: seen[1] }
      end
    end

    def aligned?(first, second, third)
      direction(first, second) == direction(first, third) && between?(first, third).include?(second)
    end

    def direction(from, to)
      df = file(to) - file(from)
      dr = rank(to) - rank(from)
      return [0, 0] if df.zero? && dr.zero?

      gcd = df.abs.gcd(dr.abs)
      [df / gcd, dr / gcd]
    end

    def between?(from, to)
      df = file(to) - file(from)
      dr = rank(to) - rank(from)
      return [] unless df.zero? || dr.zero? || df.abs == dr.abs

      step_f = df.zero? ? 0 : df / df.abs
      step_r = dr.zero? ? 0 : dr / dr.abs
      squares_between = []
      f = file(from) + step_f
      r = rank(from) + step_r
      until f == file(to) && r == rank(to)
        squares_between << square(f, r)
        f += step_f
        r += step_r
      end
      squares_between
    end

    def signature
      board = squares.map { |piece| piece || "." }.join
      "#{board} #{turn} #{castling} #{ep || '-'}"
    end

    def to_fen
      ranks = 7.downto(0).map do |rank_index|
        empty = 0
        row = +""
        8.times do |file_index|
          piece = squares[square(file_index, rank_index)]
          if piece.nil?
            empty += 1
          else
            row << empty.to_s if empty.positive?
            empty = 0
            row << piece
          end
        end
        row << empty.to_s if empty.positive?
        row
      end
      ep_text = ep ? self.class.algebraic(ep) : "-"
      "#{ranks.join('/')} #{turn} #{castling} #{ep_text} #{halfmove} #{fullmove}"
    end

    def ascii
      rows = 7.downto(0).map do |rank_index|
        cells = 8.times.map { |file_index| squares[square(file_index, rank_index)] || "." }
        "#{rank_index + 1} #{cells.join(' ')}"
      end
      "#{rows.join("\n")}\n  a b c d e f g h"
    end

    def perft(depth)
      return 1 if depth.zero?

      count = 0
      legal_moves.each do |move|
        apply!(move)
        count += perft(depth - 1)
        undo!
      end
      count
    end

    def gives_check?(move)
      apply!(move)
      check = in_check?
      undo!
      check
    end

    # Squares a piece can step to, including empty squares. Pins and checks are ignored.
    def destinations(origin)
      piece = squares[origin]
      return [] unless piece

      found = []
      case kind(piece)
      when "p"
        dir = white?(piece) ? 1 : -1
        [-1, 1].each do |df|
          f = file(origin) + df
          r = rank(origin) + dir
          next unless on_board?(f, r)

          found << square(f, r)
        end
      when "n"
        empty_or_enemy(origin, KNIGHT_OFFSETS, found)
      when "k"
        empty_or_enemy(origin, KING_OFFSETS, found)
      when "b"
        slide_squares(origin, BISHOP_DIRS, found)
      when "r"
        slide_squares(origin, ROOK_DIRS, found)
      when "q"
        slide_squares(origin, BISHOP_DIRS + ROOK_DIRS, found)
      end
      found
    end

    private

    def load_fen(fen)
      parts = fen.to_s.strip.split
      raise InvalidFen, "FEN must have at least 4 fields" if parts.length < 4

      placement, turn, castling, ep_text = parts
      half = parts[4] || "0"
      full = parts[5] || "1"
      raise InvalidFen, "side to move must be w or b" unless %w[w b].include?(turn)
      raise InvalidFen, "invalid castling rights" unless castling.match?(/\A(-|[KQkq]+)\z/)
      raise InvalidFen, "invalid halfmove clock" unless half.match?(/\A\d+\z/)
      raise InvalidFen, "invalid fullmove number" unless full.match?(/\A\d+\z/)

      @squares = Array.new(64)
      ranks = placement.split("/")
      raise InvalidFen, "FEN board must have 8 ranks" unless ranks.length == 8

      ranks.each_with_index do |row, index|
        rank_index = 7 - index
        file_index = 0
        row.each_char do |char|
          if char.match?(/\d/)
            file_index += char.to_i
          elsif char.match?(/[pnbrqkPNBRQK]/)
            raise InvalidFen, "rank #{8 - index} has more than 8 files" if file_index > 7

            @squares[square(file_index, rank_index)] = char
            file_index += 1
          else
            raise InvalidFen, "invalid piece #{char}"
          end
        end
        raise InvalidFen, "rank #{8 - index} does not have 8 files" unless file_index == 8
      end

      @turn = turn
      @castling = castling
      @ep = ep_text == "-" ? nil : self.class.parse_square(ep_text)
      @halfmove = half.to_i
      @fullmove = full.to_i
      @wk = squares.index("K")
      @bk = squares.index("k")
      raise InvalidFen, "white king is missing" unless @wk
      raise InvalidFen, "black king is missing" unless @bk
      raise InvalidFen, "position is illegal: the opponent is in check" if in_check?(enemy)

      @legal = nil
    end

    def pseudo_legal_moves
      moves = []
      each_piece do |piece, origin|
        next unless color_of(piece) == turn

        case kind(piece)
        when "p" then pawn_moves(origin, piece, moves)
        when "n" then leap_moves(origin, piece, KNIGHT_OFFSETS, moves)
        when "b" then slide_moves(origin, piece, BISHOP_DIRS, moves)
        when "r" then slide_moves(origin, piece, ROOK_DIRS, moves)
        when "q" then slide_moves(origin, piece, BISHOP_DIRS + ROOK_DIRS, moves)
        when "k" then king_moves(origin, piece, moves)
        end
      end
      moves
    end

    def pawn_moves(origin, piece, moves)
      dir = white?(piece) ? 1 : -1
      start_rank = white?(piece) ? 1 : 6
      last_rank = white?(piece) ? 7 : 0
      f = file(origin)
      r = rank(origin)
      forward = square(f, r + dir)
      if on_board?(f, r + dir) && squares[forward].nil?
        add_pawn_move(origin, forward, r + dir == last_rank, moves)
        if r == start_rank
          jump = square(f, r + (2 * dir))
          moves << build_move(origin, jump) if squares[jump].nil?
        end
      end

      [-1, 1].each do |df|
        next unless on_board?(f + df, r + dir)

        target = square(f + df, r + dir)
        occupant = squares[target]
        if occupant && color_of(occupant) != color_of(piece)
          add_pawn_move(origin, target, r + dir == last_rank, moves)
        end
        moves << build_move(origin, target, en_passant: true) if ep == target
      end
    end

    def add_pawn_move(origin, target, promote, moves)
      if promote
        %w[q r b n].each { |piece| moves << build_move(origin, target, promotion: piece) }
      else
        moves << build_move(origin, target)
      end
    end

    def leap_moves(origin, piece, offsets, moves)
      offsets.each do |df, dr|
        f = file(origin) + df
        r = rank(origin) + dr
        next unless on_board?(f, r)

        target = square(f, r)
        occupant = squares[target]
        moves << build_move(origin, target) if occupant.nil? || color_of(occupant) != color_of(piece)
      end
    end

    def slide_moves(origin, piece, dirs, moves)
      dirs.each do |df, dr|
        f = file(origin)
        r = rank(origin)
        loop do
          f += df
          r += dr
          break unless on_board?(f, r)

          target = square(f, r)
          occupant = squares[target]
          if occupant.nil?
            moves << build_move(origin, target)
          else
            moves << build_move(origin, target) if color_of(occupant) != color_of(piece)
            break
          end
        end
      end
    end

    def king_moves(origin, piece, moves)
      leap_moves(origin, piece, KING_OFFSETS, moves)
      return if in_check?(turn)

      if white?(piece) && origin == 4
        if castling.include?("K") && squares[7] == "R" && squares[5].nil? && squares[6].nil? &&
           !attacked_by?(5, "b") && !attacked_by?(6, "b")
          moves << build_move(4, 6, castle: "K")
        end
        if castling.include?("Q") && squares[0] == "R" && squares[1].nil? && squares[2].nil? && squares[3].nil? &&
           !attacked_by?(3, "b") && !attacked_by?(2, "b")
          moves << build_move(4, 2, castle: "Q")
        end
      elsif !white?(piece) && origin == 60
        if castling.include?("k") && squares[63] == "r" && squares[61].nil? && squares[62].nil? &&
           !attacked_by?(61, "w") && !attacked_by?(62, "w")
          moves << build_move(60, 62, castle: "k")
        end
        if castling.include?("q") && squares[56] == "r" && squares[57].nil? && squares[58].nil? && squares[59].nil? &&
           !attacked_by?(59, "w") && !attacked_by?(58, "w")
          moves << build_move(60, 58, castle: "q")
        end
      end
    end

    def build_move(from, to, promotion: nil, castle: nil, en_passant: false)
      Move.new(from: from, to: to, promotion: promotion, castle: castle, en_passant: en_passant)
    end

    def leap_targets(origin, offsets, targets)
      piece = squares[origin]
      offsets.each do |df, dr|
        f = file(origin) + df
        r = rank(origin) + dr
        next unless on_board?(f, r)

        index = square(f, r)
        occupant = squares[index]
        targets << index if occupant && color_of(occupant) != color_of(piece)
      end
    end

    def empty_or_enemy(origin, offsets, found)
      piece = squares[origin]
      offsets.each do |df, dr|
        f = file(origin) + df
        r = rank(origin) + dr
        next unless on_board?(f, r)

        index = square(f, r)
        occupant = squares[index]
        next if occupant && kind(occupant) == "k"

        found << index if occupant.nil? || color_of(occupant) != color_of(piece)
      end
    end

    def slide_squares(origin, dirs, found)
      piece = squares[origin]
      dirs.each do |df, dr|
        f = file(origin)
        r = rank(origin)
        loop do
          f += df
          r += dr
          break unless on_board?(f, r)

          index = square(f, r)
          occupant = squares[index]
          if occupant.nil?
            found << index
          else
            found << index if color_of(occupant) != color_of(piece) && kind(occupant) != "k"
            break
          end
        end
      end
    end

    def slide_targets(origin, dirs, targets)
      piece = squares[origin]
      dirs.each do |df, dr|
        f = file(origin)
        r = rank(origin)
        loop do
          f += df
          r += dr
          break unless on_board?(f, r)

          index = square(f, r)
          occupant = squares[index]
          next unless occupant

          targets << index if color_of(occupant) != color_of(piece)
          break
        end
      end
    end

    def ray_attackers(target, df, dr, color, kinds)
      f = file(target)
      r = rank(target)
      found = []
      loop do
        f += df
        r += dr
        break unless on_board?(f, r)

        index = square(f, r)
        piece = squares[index]
        next unless piece

        found << index if color_of(piece) == color && kinds.include?(kind(piece))
        break
      end
      found
    end

    def update_castling(move, piece)
      rights = @castling.dup
      if kind(piece) == "k"
        rights = white?(piece) ? rights.delete("K").delete("Q") : rights.delete("k").delete("q")
      end
      { 0 => "Q", 7 => "K", 56 => "q", 63 => "k" }.each do |index, right|
        rights = rights.delete(right) if move.from == index || move.to == index
      end
      @castling = rights.empty? ? "-" : rights
    end

    def update_en_passant(move, piece)
      @ep = nil
      return unless kind(piece) == "p" && (rank(move.to) - rank(move.from)).abs == 2

      @ep = (move.from + move.to) / 2
    end
  end
end
