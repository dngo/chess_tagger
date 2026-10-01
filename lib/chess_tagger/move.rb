# frozen_string_literal: true

module ChessTagger
  Move = Data.define(:from, :to, :promotion, :castle, :en_passant) do
    def uci
      notation = Position.algebraic(from) + Position.algebraic(to)
      promotion ? notation + promotion : notation
    end

    def capture?
      en_passant
    end
  end
end
