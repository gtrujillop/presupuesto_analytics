require 'money'
# == Schema Information
#
# Table name: presupuestos
#
#  id             :bigint           not null, primary key
#  descripcion    :string
#  disponibilidad :decimal(, )      default(0.0)
#  egreso         :decimal(, )      default(0.0)
#  reserva        :decimal(, )      default(0.0)
#  valor_inicial  :decimal(, )
#  proyecto_id    :bigint
#  rubro_id       :bigint
#
# Indexes
#
#  fki_fk_presupuestos_proyectos      (proyecto_id)
#  fki_fk_presupuestos_rubros         (rubro_id)
#  index_presupuestos_on_proyecto_id  (proyecto_id)
#  index_presupuestos_on_rubro_id     (rubro_id)
#
# Foreign Keys
#
#  fk_presupuestos_proyectos  (proyecto_id => proyectos.id)
#  fk_presupuestos_rubros     (rubro_id => rubros.id)
#
class Presupuesto < ApplicationRecord
  require 'csv'
  include Pagy::Backend

  belongs_to :rubro, foreign_key: :rubro_id
  belongs_to :proyecto, foreign_key: :proyecto_id

  validates :disponibilidad, numericality: true
  validates :egreso, numericality: true
  validates :reserva, numericality: true
  validates :valor_inicial, numericality: true

  # Ids permitidos en las opciones de filtros
  ACCEPTED_FILTER_OPTIONS = {
    por_facultad: Facultad.pluck(:id),
    por_grupo: Grupo.pluck(:id),
    por_semillero: Semillero.pluck(:id),
    por_anio: Semillero.pluck(:id),
    por_rubro: Rubro.pluck(:id),
    por_proyecto: Proyecto.pluck(:id)
  }.freeze

  scope :by_facultad, ->(facultad_id) { joins("INNER JOIN proyectos ON proyectos.id = presupuestos.proyecto_id").where("proyectos.facultad_id = ?", facultad_id) }
  scope :by_grupo, ->(grupo_id) { joins("INNER JOIN proyectos ON proyectos.id = presupuestos.proyecto_id").where("proyectos.grupo_id = ?", grupo_id) }
  scope :by_semillero, ->(semillero_id) { joins("INNER JOIN proyectos ON proyectos.id = presupuestos.proyecto_id").where("proyectos.semillero_id = ?", semillero_id) }
  scope :by_year, ->(year) { joins("INNER JOIN proyectos ON proyectos.id = presupuestos.proyecto_id").where("extract(year from proyectos.fecha_inicio) = ?", year) }
  scope :by_rubro, ->(rubro_id) { where("presupuestos.rubro_id = ?", rubro_id) }
  scope :by_proyecto, ->(proyecto_id) { where("presupuestos.proyecto_id = ?", proyecto_id) }

  # def self.por_proyecto
  #   sql = <<-SQL
  #     SELECT 
  #       pr.numero_proyecto,
  #       fa.nombre,
  #       pr.fecha_inicio,
  #       pr.fecha_fin,
  #       #{base_columns_for_presupuestos_report}
  #       FROM presupuestos pre
  #       INNER JOIN proyectos pr ON pr.id = pre.proyecto_id
  #       INNER JOIN facultades fa ON pr.facultad_id = fa.id
  #       GROUP BY pr.id, fa.id;
  #   SQL
  #   formatted_results(sql)
  # end

  def self.por_facultad
    sql_presupuestos = <<-SQL
      SELECT 
        fa.id, fa.nombre AS nombre_facultad,
        #{base_columns_for_presupuestos_report}
        FROM presupuestos pre
        INNER JOIN proyectos pr ON pr.id = pre.proyecto_id
        INNER JOIN facultades fa ON pr.facultad_id = fa.id
        GROUP BY fa.id;
    SQL
    sql_presupuesto_inicial = <<-SQL
      SELECT
        fa.id, fa.nombre AS nombre_facultad,
        SUM(pri.valor_inicial) AS presupuesto_inicial
        FROM presupuesto_inicial_proyectos pri
        INNER JOIN proyectos pr ON pr.id = pri.proyecto_id
        INNER JOIN facultades fa ON pr.facultad_id = fa.id
        GROUP BY fa.id
    SQL
    formatted_results(sql1: sql_presupuestos, sql2: sql_presupuesto_inicial, join_column: 'nombre_facultad')
  end

  def self.por_grupo
    sql_presupuestos = <<-SQL
      SELECT 
        gr.id, gr.nombre AS nombre_grupo,
        #{base_columns_for_presupuestos_report}
        FROM presupuestos pre
        INNER JOIN proyectos pr ON pr.id = pre.proyecto_id
        INNER JOIN grupos gr ON gr.id = pr.grupo_id
        GROUP BY gr.id
    SQL

    sql_presupuesto_inicial = <<-SQL
      SELECT 
        gr.id, gr.nombre AS nombre_grupo,
        SUM(pri.valor_inicial) AS presupuesto_inicial
        FROM presupuesto_inicial_proyectos pri
        INNER JOIN proyectos pr ON pr.id = pri.proyecto_id
        INNER JOIN grupos gr ON gr.id = pr.grupo_id
        GROUP BY gr.id
    SQL

    formatted_results(sql1: sql_presupuestos, sql2: sql_presupuesto_inicial, join_column: 'nombre_grupo')
  end

  def self.por_rubro
    sql_presupuestos = <<-SQL
      SELECT 
        ru.id, ru.nombre AS nombre_rubro,
        #{base_columns_for_presupuestos_report}
        FROM presupuestos pre
        INNER JOIN rubros ru ON ru.id = pre.rubro_id
        GROUP BY ru.id
    SQL
    sql_presupuesto_inicial = <<-SQL
      SELECT 
        ru.id, ru.nombre AS nombre_rubro,
        SUM(pri.valor_inicial) AS presupuesto_inicial
        FROM presupuesto_inicial_proyectos pri
        INNER JOIN rubros ru ON ru.id = pri.rubro_id
        GROUP BY ru.id
    SQL
    formatted_results(sql1: sql_presupuestos, sql2: sql_presupuesto_inicial, join_column: 'nombre_rubro')
  end

  def self.por_anio
    sql_presupuestos = <<-SQL
      SELECT 
        extract(year from pr.fecha_inicio) as anio_inicio,
        #{base_columns_for_presupuestos_report}
        FROM presupuestos pre
        INNER JOIN proyectos pr ON pr.id = pre.proyecto_id
        GROUP BY 1
    SQL
    
    sql_presupuesto_inicial = <<-SQL
      SELECT 
        extract(year from pr.fecha_inicio) as anio_inicio,
        SUM(pri.valor_inicial) AS presupuesto_inicial
        FROM presupuesto_inicial_proyectos pri
        INNER JOIN proyectos pr ON pr.id = pri.proyecto_id
        GROUP BY 1
    SQL
    formatted_results(sql1: sql_presupuestos, sql2: sql_presupuesto_inicial, join_column: 'anio_inicio')
  end

  def self.csv_import(file)
    Presupuesto.transaction do
      presupuestos = []
      begin
        CSV.foreach(file.path, headers: true, encoding:'iso-8859-1:utf-8') do |row|
          rubro = row[0]
          numero_proyecto = row[1]
          @rubro = Rubro.where(['lower(nombre) = ?', rubro.downcase]).first
          raise ActiveRecord::RecordNotFound.new("No se encontró rubro: #{rubro}") if @rubro.blank?

          @proyecto = Proyecto.find_by(numero_proyecto: numero_proyecto)
          raise  ActiveRecord::RecordNotFound.new("No se encontró proyecto: #{numero_proyecto}") if @proyecto.blank?
          
          element = row.to_h
          element = element.slice('valor_inicial', 'disponibilidad', 'descripcion', 'egreso', 'reserva')
          element.merge!({'proyecto_id' => @proyecto.id, 'rubro_id' => @rubro.id})
          presupuestos << element
        end
        Presupuesto.create!(presupuestos)
      rescue ActiveRecord::ActiveRecordError => e
        logger.error e.message
        # return false
        raise ActiveRecord::ActiveRecordError.new("No se pudo importar CSV #{e.message}")
      end
    end
  end
  
  # report_type es el tipo de reporte que se desea consultar
  # filter_option son las opciones que tiene el tipo de reporte para filtrar
  def self.grid_data(report_type: nil, filter_option: nil)
    # Validar que los paràmetros que envìa el usuario son correctos
    if report_type.downcase == "por_facultad" && filter_option.present?
      by_facultad(filter_option)
    elsif report_type.downcase == "por_grupo" && filter_option.present?
      by_grupo(filter_option)
    elsif report_type.downcase == "por_semillero" && filter_option.present?
      by_semillero(filter_option)
    elsif report_type.downcase == "por_anio" && filter_option.present?
      by_year(filter_option)
    elsif report_type.downcase == "por_rubro" && filter_option.present?
      by_rubro(filter_option)
    elsif report_type.downcase == "por_proyecto" && filter_option.present?
      by_proyecto(filter_option)
    else
      Presupuesto.all
    end
  end

  private

  # sql1 es el parámetro de la consulta de presupuestos
  # sql2 es el parámetro de la consulta de valores iniciales
  # join_column es el campo por el que se van a unir sql1 y sql2
  def self.formatted_results(sql1: '', sql2: '', join_column: '')
    # results_presupuesto_inicial = ActiveRecord::Base.connection.exec_query(sql2).to_a.map do |res|
    #   res['presupuesto_inicial'] = res['presupuesto_inicial'].to_f
    #   res
    # end
    ActiveRecord::Base.connection.exec_query(sql1).to_a.map do |res|
      # TODO Refactor
      # if results_presupuesto_inicial.present?
      #   res['presupuesto_inicial'] = results_presupuesto_inicial.find do |rpi| 
      #     res[join_column].to_s.downcase == rpi[join_column].to_s.downcase 
      #   end['presupuesto_inicial']
      # else
      # end
      res['presupuesto_inicial'] = res['presupuesto_inicial'].to_i
      res['anio_inicio'] = res['anio_inicio'].to_i
      res['disponibilidad_total'] = res['disponibilidad_total'].to_f
      res['egreso_total'] = res['egreso_total'].to_f
      res['reserva_total'] = res['reserva_total'].to_f
      res
    end
  end

  def self.base_columns_for_presupuestos_report
    "SUM(pre.disponibilidad) AS disponibilidad_total,
     SUM(pre.egreso) AS egreso_total,
     SUM(pre.reserva) AS reserva_total,
     SUM(pre.valor_inicial) AS presupuesto_inicial"
  end
end
