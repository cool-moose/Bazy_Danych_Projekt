
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'role_manager') THEN
        CREATE ROLE role_manager;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'role_receptionist') THEN
        CREATE ROLE role_receptionist;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'role_accountant') THEN
        CREATE ROLE role_accountant;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'role_cleaning') THEN
        CREATE ROLE role_cleaning;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'role_readonly') THEN
        CREATE ROLE role_readonly;
    END IF;
END
$$;

-- Nadanie uprawnień do schematu public dla ról
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'admin@hotel.com') THEN
        CREATE ROLE "admin@hotel.com" LOGIN PASSWORD 'admin';
        GRANT role_manager TO "admin@hotel.com";
    END IF;
END
$$;

INSERT INTO public.employees (
    first_name, last_name, position, phone, email, hire_date
)
SELECT 'Admin', 'System', 'manager', '000000000', 'admin@hotel.com', CURRENT_DATE
WHERE NOT EXISTS (SELECT 1 FROM public.employees WHERE email = 'admin@hotel.com');


DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'receptionist@hotel.com') THEN
        CREATE ROLE "receptionist@hotel.com" LOGIN PASSWORD 'receptionist';
        GRANT role_receptionist TO "receptionist@hotel.com";
    END IF;
END
$$;

INSERT INTO public.employees (
    first_name, last_name, position, phone, email, hire_date
)
SELECT 'Anna', 'Kowalska', 'receptionist', '432859203', 'receptionist@hotel.com', CURRENT_DATE
WHERE NOT EXISTS (SELECT 1 FROM public.employees WHERE email = 'receptionist@hotel.com');


DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'accountant@hotel.com') THEN
        CREATE ROLE "accountant@hotel.com" LOGIN PASSWORD 'accountant';
        GRANT role_accountant TO "accountant@hotel.com";
    END IF;
END
$$;

INSERT INTO public.employees (
    first_name, last_name, position, phone, email, hire_date
)
SELECT 'Piotr', 'Nowak', 'accountant', '932539203', 'accountant@hotel.com', CURRENT_DATE
WHERE NOT EXISTS (SELECT 1 FROM public.employees WHERE email = 'accountant@hotel.com');


DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'cleaning@hotel.com') THEN
        CREATE ROLE "cleaning@hotel.com" LOGIN PASSWORD 'cleaning';
        GRANT role_cleaning TO "cleaning@hotel.com";
    END IF;
END
$$;

INSERT INTO public.employees (
    first_name, last_name, position, phone, email, hire_date
)
SELECT 'Szymon', 'Szymczak', 'cleaning', '483258394', 'cleaning@hotel.com', CURRENT_DATE
WHERE NOT EXISTS (SELECT 1 FROM public.employees WHERE email = 'cleaning@hotel.com');


DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'readonly@hotel.com') THEN
        CREATE ROLE "readonly@hotel.com" LOGIN PASSWORD 'readonly';
        GRANT role_readonly TO "readonly@hotel.com";
    END IF;
END
$$;

INSERT INTO public.employees (
    first_name, last_name, position, phone, email, hire_date
)
SELECT 'Readonly', 'System', 'readonly', '000000000', 'readonly@hotel.com', CURRENT_DATE
WHERE NOT EXISTS (SELECT 1 FROM public.employees WHERE email = 'readonly@hotel.com');

