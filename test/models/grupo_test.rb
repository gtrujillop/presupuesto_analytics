# == Schema Information
#
# Table name: grupos
#
#  id                                        :bigint           not null, primary key
#  nombre                                    :string
#  facultad_id(Identificador de la facultad) :bigint
#  programa_id                               :bigint
#
# Indexes
#
#  fki_fk_grupos_facultades     (facultad_id)
#  index_grupos_on_facultad_id  (facultad_id)
#  index_grupos_on_programa_id  (programa_id)
#
# Foreign Keys
#
#  fk_grupos_facultades  (facultad_id => facultades.id) ON DELETE => cascade ON UPDATE => cascade
#  fk_rails_...          (programa_id => programas.id)
#
require "test_helper"

class GrupoTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end