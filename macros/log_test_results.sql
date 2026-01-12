{% macro log_test_results() %}
  {% if execute %}
    
    {# Define your audit table location #}
    {% set audit_schema = target.schema ~ '_dbt_test_audit' %}
    {% set audit_table = 'test_results_history' %}
    
    {# Create audit table if it doesn't exist #}
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
    
    {# Process each test result #}
    {% for result in results %}
      {% if result.node.resource_type == 'test' %}
        
        {# Extract metadata from result #}
        {% set table_name = result.node.get('attached_node', '') | replace('model.', '') | replace('source.', '') %}
        {% set column_name = result.node.get('column_name', '') %}
        {% set test_name = result.node.test_metadata.name %}
        {% set failed_count = result.failures | int %}
        {% set test_status = result.status %}
        {% set test_unique_id = result.node.unique_id %}
        {% set invocation_id = invocation_id %}
        {% set run_at = run_started_at %}
        
        {# Only process if store_failures is enabled and test failed #}
        {% if result.node.config.get('store_failures', false) and failed_count > 0 %}
          
          {# Get the stored failures table name #}
          {% set failure_table = result.node.relation %}
          
          {# Query failed rows and convert to JSON #}
          {% set failed_rows_query %}
            select object_construct(*) as failed_row
            from  failure_table 
            limit 100
          {% endset %}
          
          {% set failed_rows_result = run_query(failed_rows_query) %}
          
          {# Build array of failed rows #}
          {% set failed_rows_array = [] %}
          {% if failed_rows_result %}
            {% for row in failed_rows_result.rows %}
              {% do failed_rows_array.append(row[0]) %}
            {% endfor %}
          {% endif %}
          
          {% set failed_rows_json = failed_rows_array | tojson %}
          
        {% else %}
          {% set failed_rows_json = 'null' %}
        {% endif %}
        
        {# Insert into audit table #}
        {% set insert_sql %}
          insert into {{ target.database }}.{{ audit_schema }}.{{ audit_table }}
            (table_name, column_name, test, failed_count, failed_rows, run_at, test_status, test_unique_id, invocation_id)
          values (
            ' table_name ',
            ' column_name ',
            ' test_name ',
             failed_count ,
            parse_json(' failed_rows_json | replace("'", '"') '),
            ' run_at ',
            ' test_status ',
            ' test_unique_id ',
            ' invocation_id '
          )
        {% endset %}
        
        {% do run_query(insert_sql) %}
        
      {% endif %}
    {% endfor %}
    
     log("✅ Test results logged to " ~ target.database ~ "." ~ audit_schema ~ "." ~ audit_table, info=true) 
    
  {% endif %}
{% endmacro %}