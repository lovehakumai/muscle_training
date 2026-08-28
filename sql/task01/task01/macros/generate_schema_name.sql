{% macro generate_schema_name(custom_schema_name, node) %}
    {%- if target_name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name }}
    {%- else -%}
        {{ target.schema }}_{{custom_schema_name | trim}}
    {%- endif -%}
{% endmacro %}