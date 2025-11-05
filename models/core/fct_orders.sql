with customers as (
    select * 
    from {{ ref('stg_customers') }}
),

orders as (
    select * 
    from {{ ref('stg_orders') }}
),

customer_orders as (
    select
        customer_id,
        min(order_date) as first_order_date
    from orders
    group by customer_id
),

final as (
    select
        o.order_id,
        o.order_date,
        o.status,
        c.customer_id,
        c.first_name,
        c.last_name,
        co.first_order_date,
        -- Note that we've used a macro for this so that the appropriate DATEDIFF syntax is used for each respective data platform
        {{ datediff('first_order_date', 'order_date', 'day') }} as days_as_customer_at_purchase
    from orders o
    left join customers c using (customer_id)
    left join customer_orders co using (customer_id)
)

select * from final