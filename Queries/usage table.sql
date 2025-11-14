-- public."usage" definition

-- Drop table

-- DROP TABLE public."usage";

CREATE TABLE public."usage" (
	requests public."record_id" NOT NULL,
	"module" public."config_json" NOT NULL,
	module_deliverable public."config_json" NOT NULL,
	customer_account_name public."single_line_text" NULL,
	customer_name public."single_line_text" NOT NULL,
	immediate_customer public."single_line_text" NOT NULL,
	solution_owner public."single_line_text" NOT NULL,
	solution_owner_practice public."single_line_text" NOT NULL,
	sku public."single_line_text" NULL,
	quantity_unit public."dropdown" NOT NULL,
	micro_pricing_unit public."single_line_text" NULL,
	unit_price numeric NOT NULL,
	quantity numeric NOT NULL,
	total_price numeric NOT NULL,
	"billing_sign_off_generated_frequency " public."dropdown" NULL,
	"immediate_customers_sign_off_status " public."dropdown" NULL,
	"root_customer_sign_off " public."dropdown" NULL,
	"final_sign_off_status " public."dropdown" NOT NULL,
	immediate_signoff_datetime public.date_time NULL,
	root_signoff_datetime public.date_time NULL,
	billing_status public."dropdown" NULL,
	solution_owner_share numeric NULL,
	dept_revenue numeric NULL,
	platform_fee numeric NULL,
	status public."single_line_text" NULL
)
INHERITS (public.master_key);


-- public."usage" foreign keys

ALTER TABLE public."usage" ADD CONSTRAINT fk_requests_id FOREIGN KEY (requests) REFERENCES public.requests(in_record_id) ON DELETE CASCADE ON UPDATE CASCADE;