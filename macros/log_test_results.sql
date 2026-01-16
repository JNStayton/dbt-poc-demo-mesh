{% macro log_test_results() %}
  {% if execute %}
    
    {# 1. Define your audit table location #}
    {% set audit_schema = target.schema ~ '_dbt_test_audit' %}
    {% set audit_table = 'test_results_history' %}
    
    {# 2. Create audit schema and table #}
    {% do run_query("create schema if not exists " ~ target.database ~ "." ~ audit_schema) %}
    
    {% set create_table_sql %}
      create table if not exists {{ target.database }}.{{ audit_schema }}.{{ audit_table }}  (
        table_name varchar(500),
        column_name varchar(500),
        test varchar(500),
        failed_count integer,
        failed_rows variant,
        run_at timestamp_ntz,
        test_status varchar(50),
        test_unique_id varchar(1000),
        invocation_id varchar(500),
        created_at timestamp_ntz default current_timestamp()
      )
    {% endset %}
    {% do run_query(create_table_sql) %}
    
    {# 3. Process each test result #}
    {% for result in results %}
      {% if result.node.resource_type == 'test' %}
        
        {% set table_name = result.node.attached_node | default('') | replace('model.', '') | replace('source.', '') %}
        {% set column_name = result.node.column_name | default('') %}
        {% set test_name = result.node.test_metadata.name %}
        {% set failed_count = result.failures | int %}
        {% set test_status = result.status %}
        {% set test_unique_id = result.node.unique_id %}
        
        {# 4. Manually construct the failure table path if it exists #}
        {% set f_db = result.node.database %}
        {% set f_sch = result.node.schema %}
        {% set f_id = result.node.alias or result.node.name %}
        
        {% set insert_sql %}
          insert into {{ target.database }}.{{ audit_schema }}.{{ audit_table }}
            (table_name, column_name, test, failed_count, failed_rows, run_at, test_status, test_unique_id, invocation_id)
          
          with failure_data as (
            {% if result.node.config.get('store_failures', false) and failed_count > 0 and f_id %}
              select array_agg(object_construct(*)) as logs 
              from {{ f_db }}.{{ f_sch }}.{{ f_id }}
            {% else %}
              select parse_json('null') as logs
            {% endif %}
          )

          select 
            '{{ table_name }}',
            '{{ column_name }}',
            '{{ test_name }}',
            {{ failed_count }},
            f.logs,
            '{{ run_started_at }}'::timestamp_ntz,
            '{{ test_status }}',
            '{{ test_unique_id }}',
            '{{ invocation_id }}'
          from failure_data f
        {% endset %}
        
        {% do run_query(insert_sql) %}
        
      {% endif %}
    {% endfor %}
    
    {% do log("✅ Test results logged to " ~ target.database ~ "." ~ audit_schema ~ "." ~ audit_table, info=true) %}
    
  {% endif %}
{% endmacro %}