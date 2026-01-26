{% macro generate_source_yml_2(preview_only=true, schema_name_input=none) %}

{# recommended changes:
- adding a preview_only mode to allow for testing outputs and limiting select results
- changing how results are grabbed (instead of row[0] use row['COL_NAME']) to improve code resilience
- removing dummy tables for anchors
- adding defaults to test yaml spacing and indentation during test runs
- removing the indentation variables for faster parsing (you can add these back in if you'd like)
- removing env_vars in place of project vars 
- added data_type to columns (line 93); we can parameterize this (include_data_types=true) like in the original codegen macro
- consider moving the "update" logic to a separate macro
#}

{% if preview_only %}
{{ log("*********************************************", info=true )}}
{{ log("Preview Only - No Data Will Be Changed") }}
{% endif %}

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
    {% if preview_only %}
    {{ log("*********************************************", info=true )}}
    {{ log("Preview only - limiting returned results to 1...", info=true) }}
    limit 1
    {% endif %}
{% endset %}

{% if execute %}
    {% set results = run_query(registry_query) %}
    {% set ns = namespace(yaml_output="", current_schema="", entity_list=[]) %}
    
    {% for row in results.rows %}
        {# Map variables from the row for legibility #}
        {% set schema = row['SOURCE_SCHEMA'] %}
        {% set table  = row['SOURCE_TABLE'] %}
        {% set desc   = row['ENTITY_DESCRIPTION'] %}
        {% set tier   = row['SOURCE_FRESHNESS_TIER'] | lower if row['SOURCE_FRESHNESS_TIER'] else '' %}
        {% set water  = row['INCREMENTAL_LOAD_WATERMARK_COLUMN'] %}

        {# Log metadata results #}
        {% if preview_only %}
        {{ log("*********************************************", info=true) }}
        {{ log("- Returned metadata -", info=true) }}
        {{ log("Schema: " ~ schema, info=true) }}
        {{ log("Table: " ~ table, info=true) }}
        {{ log("Desc: " ~ desc, info=true) }}
        {{ log("Tier: " ~ tier, info=true) }}
        {{ log("Water: " ~ water, info=true) }}
        {{ log("*********************************************", info=true )}}
        {% endif %}

        {# Set default tier to evaluate freshness yaml indentations #}
        {% if preview_only %}
            {% if not tier %}
            {{ log("No freshness tier set; defaulting to 'tier 1' for yaml syntax check...", info=true) }}
            {{ log("*********************************************", info=true )}}
                {% set tier = 'tier 1'%}
            {% endif %}
        {% endif %}

        {# Header logic for new schemas #}
        {% if schema != ns.current_schema %}
            {% set ns.yaml_output = ns.yaml_output ~ "\nversion: 2\n\nsources:\n  - name: " ~ (schema | lower) ~ "\n    tables:\n" %}
            {% set ns.current_schema = schema %}
        {% endif %}

        {# Table Entry #}
        {% set ns.yaml_output = ns.yaml_output ~ "\n      - name: " ~ table ~ "\n" %}
        {% set ns.yaml_output = ns.yaml_output ~ "        description: " ~ desc ~ "\n" %}

        {# Freshness Logic using Project Variables #}
        {% if 'tier 1' in tier or 'tier 2' in tier %}
            {% set tier_num = 'tier_1' if 'tier 1' in tier else 'tier_2' %}
            {% set warn_hrs = var(tier_num ~ '_warn_after') %}
            {% set err_hrs  = var(tier_num ~ '_error_after') %}

            {% set ns.yaml_output = ns.yaml_output ~ "        freshness:\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ "          warn_after: {count: " ~ warn_hrs ~ ", period: hour}\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ "          error_after: {count: " ~ err_hrs ~ ", period: hour}\n" %}
        {% endif %}
        
        {% set ns.yaml_output = ns.yaml_output ~ "        loaded_at_field: " ~ water ~ "\n" %}

        {# Columns Metadata Query #}
        {% set col_query %}
            SELECT COLUMN_NAME, 
            DATA_TYPE 
            FROM {{ target.database }}.INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_SCHEMA = '{{ schema | upper }}' 
              AND TABLE_NAME = '{{ table | upper }}'
        {% endset %}
        
        {% set col_results = run_query(col_query) %}
        {% set ns.yaml_output = ns.yaml_output ~ "        columns:\n" %}
        
        {% for col_row in col_results.rows %}
            {% set ns.yaml_output = ns.yaml_output ~ "          - name: " ~ col_row['COLUMN_NAME'] | lower ~ "\n" %}
            {% set ns.yaml_output = ns.yaml_output ~ "            data_type: " ~ col_row['DATA_TYPE'] | lower ~ "\n" %}
        {% endfor %}

        {% do ns.entity_list.append("'" ~ row['ENTITY_NAME'] ~ "'") %}
    {% endfor %}

    {{ log(ns.yaml_output, info=True) }}

    {# Registry Update Logic; Only update on official runs #}
    {% if not preview_only %}
    {% if ns.entity_list | length > 0 %}
        {% set update_query %}
            UPDATE {{ ref('metadata_registry_state') }}
            SET is_source_documented = 1
            WHERE entity_name IN ( {{ ns.entity_list | join(', ') }} )
        {% endset %}
        {% do run_query(update_query) %}
        {{ log("Metadata registry updated for: " ~ ns.entity_list | length ~ " entities.", info=True) }}
    {% endif %}
    {% endif %}

{% endif %}
{% endmacro %}