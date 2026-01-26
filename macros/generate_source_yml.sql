{#
name:           generate_source_yml
purpose:        Programmatically generates dbt source YAML by querying a metadata registry.
key_inputs:     Accepts an optional schema_name_input to filter the source yml at schema level
logic:          1. Query metadata_registry_view for active, undocumented entities that require source yml
                2. Manually build the source yml and groups output by the schema
                3. Update the metadata_registry_date to toggle the is_source_documented = 1 when done.

run_example:    dbt run-operation generate_source_yml
                or
                dbt run-operation generate_source_yml --args "{'schema_name_input': 'inventory'}"

after_run:      the system log contains the yml output after the run, click on the copy button on the upper right
                hand corner of the system log and copy it to a new schema yml file or an existing one, remove 
                the header and footer.

author:         Cathy Huang

change_history: 
intial_creation:  2026-01-11    chuang
   
#}

{% macro generate_source_yml(schema_name_input=none) %}

{% set registry_query %}
    SELECT 
        entity_name,                            
        entity_description,                    
        source_schema,                         
        source_table,                           
        source_freshness_tier,                  
        incremental_load_watermark_column
    FROM {{ ref('metadata_registry_view') }}
    WHERE is_source_documented = 0 
      AND is_entity_active = 1
      {% if schema_name_input is not none %}
      AND lower(source_schema) = '{{ schema_name_input | lower }}'
      {% endif %}
{% endset %}

{% set results = run_query(registry_query) %}

{% if execute and results %}
    {% set ns = namespace(yaml_output="", current_schema="", entity_list=[]) %}
    
    {# Define Indentation Spacers #}
    {% set source_indent = "  " %}      {# 2 spaces #}
    {% set table_indent  = "      " %}  {# 6 spaces #}
    {% set desc_indent   = "        " %} {# 8 spaces #}
    {% set col_indent    = "          " %} {# 10 spaces #}

    {% for row in results.rows %}
        {% set entity_name = row[0] %}
        {% set entity_desc = row[1] %}
        {% set source_schema = row[2] %}
        {% set source_table_name = row[3] %}
        {% set source_freshness_tier = row[4] %}
        {% set source_watermark_col = row[5] %}
        
        {# Header for new schemas + Boilerplate Dummy Anchors #}
        {% if source_schema != ns.current_schema %}
            {% if ns.current_schema != "" %}
                {% set ns.yaml_output = ns.yaml_output ~ "\n" %}
            {% endif %}
            
            {% set ns.yaml_output = ns.yaml_output ~ "version: 2\n\nsources:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ source_indent ~ "- name: " ~ (source_schema | lower) ~ "\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ source_indent ~ "  description: source tables from " ~ (source_schema | upper) ~ " schema\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ source_indent ~ "  database: \"{{ env_var('DBT_CLARKITBIZ_QLIK_DB', target.database) }}\"\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ source_indent ~ "  schema: " ~ (source_schema | upper) ~ "\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ source_indent ~ "  tables:\n" %}
            
            {# BOILERPLATE DUMMY TABLES #}
            {% set ns.yaml_output = ns.yaml_output ~ table_indent ~ "- name: dummy_tier_1_freshness_anchors\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "config:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  freshness: &tier_1_freshness\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "    warn_after:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      count: \"{{ env_var('DBT_TIER_1_FRESHNESS_WARN_AFTER', target.database) | int }}\"\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      period: hour\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "    error_after:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      count: \"{{ env_var('DBT_TIER_1_FRESHNESS_ERROR_AFTER', target.database) | int }}\"\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      period: hour\n" %}
            
            {% set ns.yaml_output = ns.yaml_output ~ table_indent ~ "- name: dummy_tier_2_freshness_anchors\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "config:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  freshness: &tier_2_freshness\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "    warn_after:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      count: \"{{ env_var('DBT_TIER_2_FRESHNESS_WARN_AFTER', target.database) | int }}\"\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      period: hour\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "    error_after:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      count: \"{{ env_var('DBT_TIER_2_FRESHNESS_ERROR_AFTER', target.database) | int }}\"\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "      period: hour\n" %}
            
            {% set ns.current_schema = source_schema %}
        {% endif %}

        {# 1. Table Entry #}
        {% set ns.yaml_output = ns.yaml_output ~ table_indent ~  "\n" %}
        {% set ns.yaml_output = ns.yaml_output ~ table_indent ~  "- name: " ~ source_table_name ~ "\n" %}
        {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "description: " ~ entity_desc ~ "\n" %}

        {# 2. Freshness #}
        {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "config:\n" %}
        {% set freshness_tier = source_freshness_tier | lower if source_freshness_tier else 'none' %}
        {% if 'tier 1' in freshness_tier %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  freshness: *tier_1_freshness\n" %}
        {% elif 'tier 2' in freshness_tier %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  freshness: *tier_2_freshness\n" %}
        {% else %}
            {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  freshness: null\n" %}
        {% endif %}
        {# 3. Loaded At #}
        {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "  loaded_at_field: CONVERT_TIMEZONE('America/New_York', 'UTC', " ~ source_watermark_col ~ ")\n" %}

          {# 4. Columns #}
        {% set ns.yaml_output = ns.yaml_output ~ desc_indent ~ "columns:\n" %}
        {% set db_name = env_var('DBT_CLARKITBIZ_QLIK_DB', target.database) %}
        {% set col_query %}
            SELECT COLUMN_NAME, DATA_TYPE 
            FROM {{ db_name }}.INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_SCHEMA = '{{ source_schema | upper }}' AND TABLE_NAME = '{{ source_table_name | upper }}'
        {% endset %}
        {% set col_results = run_query(col_query) %}
        
        {% for col in col_results.rows %}
            {% set ns.yaml_output = ns.yaml_output ~ col_indent ~ "- name: " ~ col[0] | lower ~ "\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ col_indent ~ "  data_type: " ~ col[1] | lower ~ "\n" %}
        {% endfor %}

        {% do ns.entity_list.append("'" ~ entity_name ~ "'") %}
    {% endfor %}

    {{ log(ns.yaml_output, info=True) }}

     {# Registry Update Logic #}
    {% if ns.entity_list | length > 0 %}
        {% set update_query %}
            UPDATE {{ ref('metadata_registry_state') }} as state
            SET is_source_documented = 1
            FROM {{ ref('meta_entity_registry') }} as meta
            WHERE state.entity_name = meta.entity_name
              AND state.is_source_documented = 0 
              AND meta.entity_name IN ( {{ ns.entity_list | join(', ') }} )
        {% endset %}
        {{ log("update_query = " ~ update_query, info=True) }}
        {% do run_query(update_query) %}
    {% endif %}

{% endif %}
{% endmacro %}