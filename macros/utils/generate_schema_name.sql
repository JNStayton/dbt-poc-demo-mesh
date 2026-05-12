{% macro default__generate_schema_name_v2(custom_schema_name, node) -%}
    {% set env_name = env_var('DBT_CLOUD_ENVIRONMENT_NAME') | lower %}
    {% set context = env_var('DBT_CLOUD_INVOCATION_CONTEXT') | lower %}

    {% set default_schema = target.schema %}

    {% if env_name == 'development' %}

        {{ default_schema }}

    {% elif context == 'ci' %}

        {{ default_schema ~ '_' ~ custom_schema_name | trim }}

    {% elif 'production' in env_name %}

        {{ custom_schema_name | trim }}

    {% else %}

        {{ default_schema ~ '_' ~ custom_schema_name | trim }}

    {% endif %}
{%- endmacro %}