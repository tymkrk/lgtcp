begin tran

declare @cutoff_date date = '2026-04-01'

;with cte_1 as
(
	select
		id_ind
		,id_field
		,id_step
		,ROW_NUMBER() OVER (PARTITION BY id_ind, id_field, id_step ORDER BY input_date desc) as rn
	from k_m_values_histo 
	where date_histo > @cutoff_date
)
,cte_2 as
(
	select 
		* 
	from cte_1 
	where rn = 1
)

,cte_3 as
(
	select
		vh.*
		,ROW_NUMBER() OVER (PARTITION BY vh.id_ind, vh.id_field, vh.id_step ORDER BY input_date desc) as rn_3
	from cte_2 c2
	left join  k_m_values_histo vh
		on c2.id_field	= vh.id_field
		and c2.id_step	= vh.id_step
		and c2.id_ind	= vh.id_ind
		and vh.date_histo < @cutoff_date
)
,cte_4 as
(
select * from cte_3 where rn_3 = 1
)
, cte_5 as
(
	select 
		c2.id_field	
		,c2.id_step	
		,c2.id_ind	
		,c4.id_value
		,c4.input_value
		,c4.input_value_int
		,c4.input_value_numeric
		,c4.input_value_date
		,c4.input_date
		,c4.id_user
		,c4.comment_value
		,c4.source_value
		,c4.date_histo
		,c4.user_histo
		,c4.id_histo
		,c4.value_type
		,c4.idSim
		,c4.typeModification
		,c4.idOrg
		,c4.input_value_plaintext
	from cte_2 c2
	left join cte_4 c4
		on c2.id_field = c4.id_field
		and c2.id_ind =	c4.id_ind
		and c2.id_step = c4.id_step
	)

merge k_m_values kmv
using cte_5 c5
	on  kmv.id_field	= c5.id_field
	and kmv.id_ind		= c5.id_ind
	and kmv.id_step		= c5.id_step
when matched and c5.id_value is not null then update
	set kmv.input_value				= c5.input_value			
	,	kmv.input_value_int			= c5.input_value_int
	,	kmv.input_value_numeric		= c5.input_value_numeric
	,	kmv.input_value_date		= c5.input_value_date
	,	kmv.input_date				= c5.input_date
	,	kmv.id_user					= c5.id_user
	,	kmv.comment_value			= c5.comment_value
	,	kmv.source_value			= c5.source_value
	,	kmv.typeModification		= c5.typeModification
	,	kmv.idOrg					= c5.idOrg
when matched and c5.id_value is null then delete;

delete 	from k_m_values_histo 
where date_histo > @cutoff_date



rollback

