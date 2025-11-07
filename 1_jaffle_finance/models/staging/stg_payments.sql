with payments as (
    select * from {{ source('stripe', 'payment') }}
),

final as (
    select 
        id as payment_id,
        orderID as order_id,
        paymentMethod as payment_method,
        amount,
        created as payment_date 
    from payments
)

select * from final