# frozen_string_literal: true

require "minitest/autorun"
require "chess_tagger"

class TaggerTest < Minitest::Test
  def test_starting_position_has_no_tactical_tags
    assert_equal [], ChessTagger.tag("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
  end

  def test_catalog_lists_the_research_motifs
    tags = ChessTagger::TAGS

    %w[fork pin skewer].each { |tag| assert_includes tags, tag }
    assert_includes tags, "mate in 1"
    assert_includes tags, "discovered attack"
    assert_includes tags, "discovered check"
    assert_includes tags, "double check"
    assert_includes tags, "double attack"
    assert_includes tags, "deflection"
    assert_includes tags, "decoy"
    assert_includes tags, "attraction"
    assert_includes tags, "removing the defender"
    assert_includes tags, "overloading"
    assert_includes tags, "interference"
    assert_includes tags, "clearance"
    assert_includes tags, "clearance sacrifice"
    assert_includes tags, "x-ray attack"
    assert_includes tags, "zwischenzug"
    assert_includes tags, "zwischencheck"
    assert_includes tags, "undermining"
    assert_includes tags, "trapped piece"
    assert_includes tags, "desperado"
  end

  def test_knight_fork
    tags = ChessTagger.tag("4k3/8/5r2/2q5/8/8/5N2/4K3 w - - 0 1")

    assert_includes tags, "fork"
    assert_includes tags, "knight fork"
    assert_includes tags, "double attack"
  end

  def test_absolute_pin_and_hanging_piece
    tags = ChessTagger.tag("4k3/8/2n5/1B6/8/8/8/4K3 w - - 0 1")

    assert_includes tags, "pin"
    assert_includes tags, "absolute pin"
    assert_includes tags, "hanging piece"
  end

  def test_skewer
    tags = ChessTagger.tag("4k2q/8/8/8/8/8/8/R3K3 w - - 0 1")

    assert_includes tags, "skewer"
    assert_includes tags, "x-ray attack"
  end

  def test_discovered_check_and_double_check
    tags = ChessTagger.tag("4k3/8/8/8/8/8/4B3/4R1K1 w - - 0 1")

    assert_includes tags, "discovered attack"
    assert_includes tags, "discovered check"
    assert_includes tags, "double check"
    assert_includes tags, "clearance"
  end

  def test_removing_the_defender
    tags = ChessTagger.tag("4k3/8/2n5/qB6/8/8/8/R5K1 w - - 0 1")

    assert_includes tags, "removing the defender"
    assert_includes tags, "pin"
  end

  def test_back_rank_mate_in_one
    tags = ChessTagger.tag("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")

    assert_includes tags, "mate in 1"
    assert_includes tags, "back-rank mate"
    refute_includes tags, "mate in 2"
  end

  def test_smothered_mate
    tags = ChessTagger.tag("6rk/5Npp/8/8/8/8/8/7K b - - 0 1")

    assert_includes tags, "checkmate"
    assert_includes tags, "smothered mate"
    assert_includes tags, "corner mate"
  end

  def test_arabian_mate
    tags = ChessTagger.tag("k7/8/2N5/8/8/8/8/1R4K1 w - - 0 1")

    assert_includes tags, "mate in 1"
    assert_includes tags, "arabian mate"
  end

  def test_hook_mate
    tags = ChessTagger.tag("4Rk2/5pp1/3N4/2P5/8/8/8/6K1 b - - 0 1")

    assert_includes tags, "checkmate"
    assert_includes tags, "hook mate"
  end

  def test_mate_in_two
    tags = ChessTagger.tag("7k/8/8/5KQ1/8/8/8/8 w - - 0 1")

    assert_includes tags, "mate in 2"
    refute_includes tags, "mate in 1"
  end

  def test_mate_in_three
    tags = ChessTagger.tag("5rk1/p4ppp/2N5/8/8/3Q4/6K1/R7 w - - 0 1")

    assert_includes tags, "mate in 3"
    refute_includes tags, "mate in 1"
    refute_includes tags, "mate in 2"
  end

  def test_en_passant
    tags = ChessTagger.tag("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")

    assert_includes tags, "en passant"
  end

  def test_underpromotion_mate
    tags = ChessTagger.tag("8/6P1/6k1/8/8/8/8/4K3 w - - 0 1")

    assert_includes tags, "promotion"
  end

  def test_analyze_reports_the_move
    report = ChessTagger.analyze("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
    mate = report[:hits].find { |hit| hit[:tag] == "mate in 1" }

    assert_equal "white", report[:side_to_move]
    assert_includes mate[:moves], "a1a8"
  end

  def test_black_to_move_knight_fork
    tags = ChessTagger.tag("4k3/5n2/8/8/2Q5/5R2/8/4K3 b - - 0 1")

    assert_includes tags, "knight fork"
  end

  def test_insufficient_material
    assert_includes ChessTagger.tag("8/8/8/8/8/8/8/4K2k w - - 0 1"), "insufficient material"
  end

  def test_stalemate
    tags = ChessTagger.tag("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")

    assert_includes tags, "stalemate"
    refute_includes tags, "checkmate"
  end

  def test_passed_and_advanced_pawn
    tags = ChessTagger.tag("8/8/8/8/8/6P1/8/4K2k w - - 0 1")

    assert_includes tags, "passed pawn"
  end

  def test_greek_gift
    tags = ChessTagger.tag("rnbq1rk1/ppp2ppp/3b1n2/3pp3/3P4/3B1N2/PPP2PPP/RNBQK2R w KQ - 0 1")

    assert_includes tags, "greek gift"
    assert_includes tags, "demolition"
  end

  def test_overloading_seventh_rank_and_alekhine
    assert_includes ChessTagger.tag("k7/7r/5n2/3q4/8/8/2B5/3RK3 w - - 0 1"), "overloading"
    assert_includes ChessTagger.tag("6k1/R4R2/8/8/8/8/8/6K1 w - - 0 1"), "seventh rank"
    assert_includes ChessTagger.tag("8/7k/8/8/8/8/8/QRR3K1 w - - 0 1"), "alekhine's gun"
  end

  def test_pawn_fork_royal_fork_and_cross_check
    assert_includes ChessTagger.tag("4k3/8/8/2q1r3/3P4/8/8/4K3 w - - 0 1"), "pawn fork"
    assert_includes ChessTagger.tag("4k3/8/8/3q4/6N1/8/8/4K3 w - - 0 1"), "royal fork"
    assert_includes ChessTagger.tag("8/8/8/8/7q/3N4/8/4K2k w - - 0 1"), "cross-check"
  end

  def test_structural_and_endgame_tags
    assert_includes ChessTagger.tag("8/8/4k3/8/4K3/8/8/8 w - - 0 1"), "opposition"
    assert_includes ChessTagger.tag("4k3/8/8/8/8/8/8/R2r2RK w - - 0 1"), "x-ray defense"
    assert_includes ChessTagger.tag("n7/1K6/8/8/8/8/8/7k w - - 0 1"), "trapped piece"
    assert_includes ChessTagger.tag("4k3/8/3B4/2p5/1p6/8/8/1R5K w - - 0 1"), "undermining"
  end

  def test_boden_and_epaulette_mates
    assert_includes ChessTagger.tag("2kr4/p2p4/B7/8/5B2/8/8/6K1 b - - 0 1"), "boden mate"
    assert_includes ChessTagger.tag("3rkr2/4Q3/8/2B5/8/8/8/6K1 b - - 0 1"), "epaulette mate"
  end

  def test_invalid_fen
    assert_raises(ChessTagger::InvalidFen) { ChessTagger.tag("not a fen") }
  end
end
