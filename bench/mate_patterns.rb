# frozen_string_literal: true

# Scores the named checkmate patterns against Lichess puzzle themes.
#
#   ruby -Ilib bench/mate_patterns.rb lichess_db_puzzle.csv [limit]
#
# Lichess labels a mate pattern from the final position of the solution line, so
# this plays the whole line and asks MatePatterns about the mated position. That
# isolates the pattern definitions from the mate search.

require "csv"
require "chess_tagger"

LABELS = {
  "backRankMate" => "back-rank mate",
  "smotheredMate" => "smothered mate",
  "arabianMate" => "arabian mate",
  "anastasiaMate" => "anastasia mate",
  "bodenMate" => "boden mate",
  "hookMate" => "hook mate",
  "dovetailMate" => "dovetail mate",
  "doubleBishopMate" => "double bishop mate",
  "killBoxMate" => "kill box mate",
  "operaMate" => "opera mate",
  "epauletteMate" => "epaulette mate",
  "swallowstailMate" => "swallow's tail mate",
  "cornerMate" => "corner mate"
}.freeze

limit = (ARGV[1] || 5000).to_i
counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
examples = Hash.new { |hash, key| hash[key] = { missed: [], wrong: [] } }
mates = 0
unlabeled_mate_themes = Hash.new(0)

CSV.foreach(ARGV[0], headers: true) do |row|
  themes = row["Themes"].split
  next unless themes.any? { |theme| theme.start_with?("mateIn") }
  break if mates >= limit

  position = ChessTagger::Position.parse(row["FEN"])
  moves = row["Moves"].split
  solver = nil
  moves.each_with_index do |uci, index|
    move = position.legal_moves.find { |candidate| candidate.uci == uci } or break
    solver = position.turn if index == 1
    position.apply!(move)
  end
  next unless position.checkmate?

  mates += 1
  mated_by = position.enemy
  mine = ChessTagger::MatePatterns.tags(position, mated_by)
  themes.grep(/Mate\z/).each { |theme| unlabeled_mate_themes[theme] += 1 unless LABELS.key?(theme) }

  LABELS.each do |theme, tag|
    labeled = themes.include?(theme)
    emitted = mine.include?(tag)
    counts[theme][:positives] += 1 if labeled
    counts[theme][:emitted] += 1 if emitted
    counts[theme][:both] += 1 if labeled && emitted
    examples[theme][:missed] << "#{row['PuzzleId']} #{position.to_fen} #{themes.grep(/Mate\z/).join(',')}" if labeled && !emitted
    examples[theme][:wrong] << "#{row['PuzzleId']} #{position.to_fen} #{themes.grep(/Mate\z/).join(',')}" if emitted && !labeled
  end
end

puts "#{mates} mating lines"
puts format("%-18s %6s %7s %8s %7s", "theme", "n", "recall", "emitted", "prec")
LABELS.each_key do |theme|
  stat = counts[theme]
  recall = stat[:positives].zero? ? 0 : 100.0 * stat[:both] / stat[:positives]
  precision = stat[:emitted].zero? ? 0 : 100.0 * stat[:both] / stat[:emitted]
  puts format("%-18s %6d %6.1f%% %8d %6.1f%%", theme, stat[:positives], recall, stat[:emitted], precision)
end
puts "other mate labels: #{unlabeled_mate_themes.sort_by { |_, n| -n }.map { |theme, n| "#{theme}=#{n}" }.join(' ')}"

if ENV["EXAMPLES"]
  only = Regexp.new(ENV.fetch("THEME", "."))
  LABELS.each_key do |theme|
    next unless theme.match?(only)

    puts "\n#{theme} missed:\n  #{examples[theme][:missed].first(ENV["EXAMPLES"].to_i).join("\n  ")}"
    puts "#{theme} wrong:\n  #{examples[theme][:wrong].first(ENV["EXAMPLES"].to_i).join("\n  ")}"
  end
end
