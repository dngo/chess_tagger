# frozen_string_literal: true

require "minitest/autorun"
require "chess_tagger"

class PositionTest < Minitest::Test
  def test_starting_position_has_twenty_moves
    position = ChessTagger::Position.parse(ChessTagger::Position::STARTING_FEN)

    assert_equal 20, position.legal_moves.size
  end

  def test_perft_counts
    assert_equal 20, perft(ChessTagger::Position::STARTING_FEN, 1)
    assert_equal 400, perft(ChessTagger::Position::STARTING_FEN, 2)
    assert_equal 8_902, perft(ChessTagger::Position::STARTING_FEN, 3)
    assert_equal 48, perft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 1)
    assert_equal 2_039, perft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 2)
    assert_equal 14, perft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 1)
    assert_equal 191, perft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 2)
    assert_equal 6, perft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 1)
    assert_equal 44, perft("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 1)
  end

  def test_fen_round_trip
    fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    position = ChessTagger::Position.parse(fen)

    assert_equal fen, position.to_fen
  end

  def test_rejects_a_king_left_in_check
    error = assert_raises(ChessTagger::InvalidFen) do
      ChessTagger::Position.parse("k7/8/8/8/8/8/8/R3K3 w - - 0 1")
    end

    assert_match(/in check/, error.message)
  end

  def test_en_passant_capture
    position = ChessTagger::Position.parse("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
    capture = position.legal_moves.find { |move| move.en_passant && move.uci == "e5f6" }

    refute_nil capture
    position.apply!(capture)

    assert_nil position.squares[ChessTagger::Position.parse_square("f5")]
    assert_equal "P", position.squares[ChessTagger::Position.parse_square("f6")]
  end

  def test_castling_moves_the_rook
    position = ChessTagger::Position.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    castle = position.legal_moves.find { |move| move.castle == "K" }

    position.apply!(castle)

    assert_equal "K", position.squares[ChessTagger::Position.parse_square("g1")]
    assert_equal "R", position.squares[ChessTagger::Position.parse_square("f1")]
    assert_nil position.squares[ChessTagger::Position.parse_square("e1")]
  end

  def test_promotion
    position = ChessTagger::Position.parse("8/P7/8/8/8/8/8/4K2k w - - 0 1")
    queen = position.legal_moves.find { |move| move.uci == "a7a8q" }

    refute_nil queen
    position.apply!(queen)

    assert_equal "Q", position.squares[ChessTagger::Position.parse_square("a8")]
  end

  private

  def perft(fen, depth)
    ChessTagger::Position.parse(fen).perft(depth)
  end
end
