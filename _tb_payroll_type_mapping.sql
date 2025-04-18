

CREATE TABLE [dbo].[_tb_payroll_type_mapping](
	[year] [int] NOT NULL,
	[payroll_type_code] [nvarchar](20) NOT NULL,
	[target_field_code] [nvarchar](510) NULL,
	[paid_field_code] [nvarchar](510) NULL,
	[target_min_field_code] [nvarchar](510) NULL,
	[target_max_field_code] [nvarchar](510) NULL,
	[plan_id] [int] NULL,
	[Id] [int] IDENTITY(1,1) NOT NULL
) ON [PRIMARY]
GO


