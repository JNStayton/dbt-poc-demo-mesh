{% macro default__generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema }}

    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}

    {%- elif custom_schema_name | trim | upper == target.schema | trim | upper -%}
        {{ target.schema }}

    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}