CREATE TABLE public.professional_sku_onboarding (
    sarthi_name                  public."record_id"      NOT NULL,
    service_role                 public."record_id"      NOT NULL,
    solution_sku                 public."record_id"      NOT NULL,

    competence_level             public."dropdown"       NOT NULL,
    status                       public."dropdown"       NOT NULL,
    percentage_service_delivered public."percentage"     NULL,

    CONSTRAINT chk_competence_level CHECK (
        competence_level IN (
            'Novice',
            'Trainee',
            'Apprentice',
            'Practioner',
            'Professional',
            'Trainer',
            'Identified'
        )
    ),

    -- CHECK: Status
    CONSTRAINT chk_status CHECK (
        status IN (
            'Active',
            'Dormant',
            'Offboarded'
        )
    ),

    -- FK: sarthi_name → users(in_record_id)
    CONSTRAINT fk_sarthi_user
        FOREIGN KEY (sarthi_name)
        REFERENCES public.users (in_record_id)
        ON DELETE CASCADE

    -- Uncomment if needed later:
    --,CONSTRAINT fk_service_role FOREIGN KEY (service_role) REFERENCES public.service_role (in_record_id)
    --,CONSTRAINT fk_solution_sku FOREIGN KEY (solution_sku) REFERENCES public.microservices (in_record_id)
)
INHERITS (public.master_key);
