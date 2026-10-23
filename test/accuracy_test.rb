# frozen_string_literal: true

require "minitest/autorun"
require "chess_tagger"

# Positions taken from Lichess puzzles, so the expectations follow how the
# community names these ideas. See bench/ for the full scoring run.
class AccuracyTest < Minitest::Test
  def hit(fen, tag)
    ChessTagger.analyze(fen)[:hits].find { |entry| entry[:tag] == tag }
  end

  def test_mate_in_two_names_the_first_move
    fen = "6k1/5ppp/r1p5/p1n1rP2/8/2P2N1P/2P3P1/3R2K1 w - - 0 22"

    assert_equal ["d1d8"], hit(fen, "mate in 2")[:moves]
  end

  def test_mate_in_two_reports_the_pattern_the_line_ends_in
    fen = "6k1/5ppp/r1p5/p1n1rP2/8/2P2N1P/2P3P1/3R2K1 w - - 0 22"

    assert_equal ["d1d8"], hit(fen, "back-rank mate")[:moves]
  end

  def test_skewer_ignores_a_pawn_behind_the_front_piece
    refute_includes ChessTagger.tag("4k3/p7/8/n7/8/8/8/R3K3 w - - 0 1"), "skewer"
  end

  def test_skewer_is_credited_to_the_move_that_creates_it
    skewer = hit("4k2q/8/8/8/8/8/8/R3K3 w - - 0 1", "skewer")

    assert_equal ["a1a8"], skewer[:moves]
  end

  def test_standing_skewer_is_not_credited_to_an_unrelated_move
    # The rook already skewers the queen and the rook behind it.
    skewer = hit("r3k3/8/8/q7/8/8/7P/RK6 w - - 0 1", "skewer")

    refute_nil skewer
    refute_includes skewer[:moves], "h2h3"
  end

  def test_kill_box_mate_needs_a_rook_backed_by_a_queen
    assert_includes ChessTagger.tag("5Rk1/5p1p/3p1p1Q/3P4/7P/q5P1/4n1K1/8 b - - 0 44"), "kill box mate"
    refute_includes ChessTagger.tag("2kr3r/p2n2pp/B1pB1bp1/5q2/8/8/PPP2PPP/3R1RK1 b - - 1 18"), "kill box mate"
  end

  def test_double_bishop_mate_is_not_boden_mate
    double = ChessTagger.tag("rnbk1r2/pppp1Bpp/8/5pB1/4p3/2PP4/P1P2PPP/R3K2R b KQ - 2 14")
    boden = ChessTagger.tag("2kr3r/p2n2pp/B1pB1bp1/5q2/8/8/PPP2PPP/3R1RK1 b - - 1 18")

    assert_includes double, "double bishop mate"
    refute_includes double, "boden mate"
    assert_includes boden, "boden mate"
    refute_includes boden, "double bishop mate"
  end

  def test_absolute_pin_is_credited_to_the_move_that_creates_it
    pin = hit("4k3/8/2n5/8/8/8/8/4KB2 w - - 0 1", "absolute pin")

    assert_equal ["f1b5"], pin[:moves]
  end

  def test_relative_pin_of_a_pawn_is_not_credited_to_a_move
    refute_includes ChessTagger.tag("4r1k1/8/2p5/8/8/8/8/K4B2 w - - 0 1"), "relative pin"
  end

  def test_relative_pin_to_a_rook_is_credited_to_the_move_that_creates_it
    pin = hit("4r1k1/8/2n5/8/8/8/8/K4B2 w - - 0 1", "relative pin")

    assert_equal ["f1b5"], pin[:moves]
  end

  def test_deflection_needs_the_defender_to_take_an_offered_piece
    fen = "r1q3k1/3nbppp/pp2p3/4B3/8/2N2Q2/PPPR1PPP/6K1 w - - 1 19"

    assert_includes hit(fen, "deflection")[:moves], "d2d7"
    # Moves that merely attack the defender are no longer called deflections.
    refute_includes hit(fen, "deflection")[:moves], "c3d5"
  end
end
