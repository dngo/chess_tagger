# frozen_string_literal: true

# Scores the tagger against Lichess puzzle themes.
#
#   JOBS=8 EXAMPLES=1 ruby -Ilib bench/lichess_puzzles.rb lichess_db_puzzle.csv [limit] [offset]
#
# The CSV comes from https://database.lichess.org/#puzzles. Each puzzle's FEN is
# the position before the opponent's last move, so the first move is applied to
# reach the position the solver faces. A theme counts as found when the tagger
# emits any tag mapped to it. "Move hit" also needs the tag's moves to include the
# solution's first move, which is what a caller filtering on the engine move sees.
# Precision treats an unlabeled tag as wrong, which understates it: Lichess labels
# the main idea of a puzzle, not every motif.

require "csv"
require "chess_tagger"

THEMES = {
  "mateIn1" => ["mate in 1"],
  "mateIn2" => ["mate in 2"],
  "mateIn3" => ["mate in 3"],
  "backRankMate" => ["back-rank mate"],
  "smotheredMate" => ["smothered mate"],
  "arabianMate" => ["arabian mate"],
  "anastasiaMate" => ["anastasia mate"],
  "bodenMate" => ["boden mate"],
  "hookMate" => ["hook mate"],
  "dovetailMate" => ["dovetail mate"],
  "doubleBishopMate" => ["double bishop mate"],
  "killBoxMate" => ["kill box mate"],
  "operaMate" => ["opera mate"],
  "fork" => ["fork", "knight fork", "pawn fork", "royal fork"],
  "pin" => ["pin", "absolute pin", "relative pin"],
  "skewer" => ["skewer"],
  "discoveredAttack" => ["discovered attack", "discovered check", "double check"],
  "doubleCheck" => ["double check"],
  "hangingPiece" => ["hanging piece"],
  "trappedPiece" => ["trapped piece"],
  "deflection" => ["deflection"],
  "attraction" => ["attraction"],
  "interference" => ["interference"],
  "clearance" => ["clearance", "clearance sacrifice"],
  "xRayAttack" => ["x-ray attack"],
  "intermezzo" => ["zwischenzug", "zwischencheck"],
  "capturingDefender" => ["removing the defender"],
  "sacrifice" => ["sacrifice", "queen sacrifice", "exchange sacrifice", "greek gift", "demolition"],
  "quietMove" => ["quiet move"],
  "promotion" => ["promotion", "underpromotion"],
  "underPromotion" => ["underpromotion"],
  "enPassant" => ["en passant"],
  "exposedKing" => ["exposed king"],
  "advancedPawn" => ["advanced pawn"],
  "attackingF2F7" => ["attacking f2/f7"],
  "zugzwang" => ["zugzwang"]
}.freeze

Score = Struct.new(:positives, :found, :move_hit, :emitted, :move_emitted, :move_emitted_labeled,
                   :emitted_labeled, :missed, :wrong) do
  def merge!(other)
    members.each do |member|
      value = self[member]
      value.is_a?(Array) ? value.concat(other[member]) : self[member] = value + other[member]
    end
  end
end

def blank_scores
  THEMES.keys.to_h { |theme| [theme, Score.new(0, 0, 0, 0, 0, 0, 0, [], [])] }
end

def score_rows(rows)
  scores = blank_scores
  tagged = 0
  failed = 0

  rows.each do |row|
    moves = row["Moves"].split
    position = ChessTagger::Position.parse(row["FEN"])
    opponent = position.legal_moves.find { |move| move.uci == moves[0] }
    next unless opponent

    fen = position.make(opponent).to_fen
    hits = ChessTagger.analyze(fen)[:hits]
    themes = row["Themes"].split
    tagged += 1

    THEMES.each do |theme, tags|
      score = scores[theme]
      mine = hits.select { |hit| tags.include?(hit[:tag]) }
      on_move = mine.select { |hit| hit[:moves].include?(moves[1]) }
      labeled = themes.include?(theme)
      score.positives += 1 if labeled
      score.emitted += 1 unless mine.empty?
      score.move_emitted += 1 unless on_move.empty?
      score.emitted_labeled += 1 if labeled && !mine.empty?
      score.move_emitted_labeled += 1 if labeled && !on_move.empty?
      score.found += 1 if labeled && !mine.empty?
      score.move_hit += 1 if labeled && !on_move.empty?
      score.missed << "#{row['PuzzleId']} #{fen} #{moves[1]}" if labeled && mine.empty?
      score.wrong << "#{row['PuzzleId']} #{fen} #{moves[1]} #{on_move.map { |hit| hit[:tag] }.uniq.join(',')}" if !labeled && !on_move.empty?
    end
  rescue StandardError => e
    failed += 1
    warn "#{row['PuzzleId']}: #{e.class}: #{e.message}" if ENV["VERBOSE"]
  end

  [scores, tagged, failed]
end

def percent(part, whole)
  whole.zero? ? 0.0 : 100.0 * part / whole
end

path, limit, offset = ARGV
abort "usage: #{$PROGRAM_NAME} puzzles.csv [limit] [offset]" unless path
limit = (limit || 2000).to_i
offset = (offset || 0).to_i
jobs = (ENV["JOBS"] || 1).to_i

rows = CSV.foreach(path, headers: true).drop(offset).first(limit)
started = Time.now

readers = (0...jobs).map do |worker|
  reader, writer = IO.pipe
  fork do
    reader.close
    writer.write(Marshal.dump(score_rows(rows.each_slice(jobs).filter_map { |slice| slice[worker] })))
    writer.close
    exit!(0)
  end
  writer.close
  reader
end

scores = blank_scores
tagged = 0
failed = 0
readers.each do |reader|
  partial, count, errors = Marshal.load(reader.read)
  partial.each { |theme, score| scores[theme].merge!(score) }
  tagged += count
  failed += errors
end
Process.waitall

puts format("%d puzzles, %d errors, %.1fs", tagged, failed, Time.now - started)
puts format("%-18s %6s %7s %8s %8s %7s %9s %9s", "theme", "n", "recall", "move-hit", "emitted", "prec", "move-emit", "move-prec")
scores.each do |theme, score|
  next if score.positives.zero? && score.emitted.zero?

  puts format("%-18s %6d %6.1f%% %7.1f%% %8d %6.1f%% %9d %8.1f%%", theme, score.positives,
              percent(score.found, score.positives), percent(score.move_hit, score.positives),
              score.emitted, percent(score.emitted_labeled, score.emitted),
              score.move_emitted, percent(score.move_emitted_labeled, score.move_emitted))
end

if ENV["EXAMPLES"]
  shown = ENV["EXAMPLES"].to_i.clamp(1, 50)
  only = Regexp.new(ENV.fetch("THEME", "."))
  scores.each do |theme, score|
    next unless theme.match?(only)

    puts "\n#{theme} missed:\n  #{score.missed.first(shown).join("\n  ")}" unless score.missed.empty?
    puts "#{theme} wrong:\n  #{score.wrong.first(shown).join("\n  ")}" unless score.wrong.empty?
  end
end
