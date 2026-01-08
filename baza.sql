--
-- PostgreSQL database dump
--

\restrict A1rmiBUBLww3kI6gN9e3tpGQZKlbtpZMZLxfUgmjEgGD8MXo83eLGqPJ5If1ZqW

-- Dumped from database version 16.11 (Ubuntu 16.11-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.11 (Ubuntu 16.11-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: status_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.status_type AS ENUM (
    'free',
    'occupied',
    'cleaning',
    'renovation'
);


ALTER TYPE public.status_type OWNER TO postgres;

--
-- Name: add_service_to_reservation(integer, integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.add_service_to_reservation(IN p_reservation_id integer, IN p_service_id integer, IN p_quantity integer DEFAULT 1, IN p_service_employee_id integer DEFAULT NULL::integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_service_price NUMERIC(10,2);
    v_total_cost NUMERIC;
    v_res_status VARCHAR(20);
BEGIN
    -- Sprawdzenie czy rezerwacja istnieje i jest aktywna
    SELECT reservation_status INTO v_res_status
    FROM reservations WHERE reservation_id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rezerwacja % nie istnieje', p_reservation_id;
    END IF;

    IF v_res_status NOT IN ('confirmed', 'checked_in') THEN
        RAISE EXCEPTION 'Nie można dodać usługi do rezerwacji o statusie: %', v_res_status;
    END IF;

    -- Cena usługi
    SELECT price INTO v_service_price
    FROM services WHERE service_id = p_service_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usługa % nie istnieje', p_service_id;
    END IF;

    v_total_cost := v_service_price * p_quantity;

    -- Dodanie zamówienia usługi
    INSERT INTO service_orders (
        reservation_id, service_id, order_date,
        quantity, total_cost, service_employee
    ) VALUES (
        p_reservation_id, p_service_id, CURRENT_DATE,
        p_quantity, v_total_cost, p_service_employee_id
    );

    -- Aktualizacja całkowitego kosztu rezerwacji
    UPDATE reservations
    SET total_cost = total_cost + v_total_cost
    WHERE reservation_id = p_reservation_id;

    RAISE NOTICE 'Usługa dodana. Dodatkowy koszt: % PLN', v_total_cost;
END;
$$;


ALTER PROCEDURE public.add_service_to_reservation(IN p_reservation_id integer, IN p_service_id integer, IN p_quantity integer, IN p_service_employee_id integer) OWNER TO postgres;

--
-- Name: calculate_reservation_cost(integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_reservation_cost(p_room_id integer, p_check_in_date date, p_check_out_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_price_per_night NUMERIC(10,2);
    v_nights INTEGER;
BEGIN
    -- Pobranie ceny za noc
    SELECT price_per_night INTO v_price_per_night
    FROM rooms WHERE room_id = p_room_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pokój o ID % nie istnieje', p_room_id;
    END IF;

    v_nights := p_check_out_date - p_check_in_date;
    IF v_nights <= 0 THEN
        RAISE EXCEPTION 'Data wymeldowania musi być późniejsza niż zameldowania';
    END IF;

    RETURN ROUND(v_price_per_night * v_nights, 2);
END;
$$;


ALTER FUNCTION public.calculate_reservation_cost(p_room_id integer, p_check_in_date date, p_check_out_date date) OWNER TO postgres;

--
-- Name: calculate_total_with_services(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_total_with_services(p_reservation_id integer) RETURNS numeric
    LANGUAGE sql
    AS $$
    SELECT
        COALESCE(r.total_cost, 0) + COALESCE(SUM(so.total_cost), 0)
    FROM reservations r
    LEFT JOIN service_orders so ON so.reservation_id = r.reservation_id
    WHERE r.reservation_id = p_reservation_id
    GROUP BY r.reservation_id, r.total_cost;
$$;


ALTER FUNCTION public.calculate_total_with_services(p_reservation_id integer) OWNER TO postgres;

--
-- Name: cancel_reservation(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_reservation(IN p_reservation_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_room_id INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT room_id, reservation_status
    INTO v_room_id, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rezerwacja % nie istnieje', p_reservation_id;
    END IF;

    IF v_status = 'checked_out' THEN
        RAISE EXCEPTION 'Rezerwacja już wymeldowana – nie można anulować';
    END IF;

    IF v_status = 'checked_in' THEN
        RAISE EXCEPTION 'Nie można anulować rezerwacji z zameldowanym gościem. Najpierw wymelduj.';
    END IF;

    -- Zmiana statusu rezerwacji
    UPDATE reservations
    SET reservation_status = 'cancelled'
    WHERE reservation_id = p_reservation_id;

    -- Zwolnienie pokoju
    UPDATE rooms
    SET status = 'free'
    WHERE room_id = v_room_id;

    RAISE NOTICE 'Rezerwacja % została anulowana, pokój zwolniony', p_reservation_id;
END;
$$;


ALTER PROCEDURE public.cancel_reservation(IN p_reservation_id integer) OWNER TO postgres;

--
-- Name: checkout(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.checkout(IN p_reservation_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_room_id INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT room_id, reservation_status
    INTO v_room_id, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rezerwacja % nie istnieje', p_reservation_id;
    END IF;

    IF v_status != 'checked_in' AND v_status != 'confirmed' THEN
        RAISE EXCEPTION 'Rezerwacja ma nieprawidłowy status: %', v_status;
    END IF;

    -- Zmiana statusu rezerwacji
    UPDATE reservations
    SET reservation_status = 'checked_out'
    WHERE reservation_id = p_reservation_id;

    -- Pokój do sprzątania
    UPDATE rooms
    SET status = 'cleaning'
    WHERE room_id = v_room_id;

    RAISE NOTICE 'Gość wymeldowany. Pokój % wymaga sprzątania', v_room_id;
END;
$$;


ALTER PROCEDURE public.checkout(IN p_reservation_id integer) OWNER TO postgres;

--
-- Name: create_db_user_and_employee(text, character varying, character varying, character varying, date, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_db_user_and_employee(IN p_password text, IN p_first_name character varying, IN p_last_name character varying, IN p_position character varying, IN p_hire_date date, IN p_email character varying, IN p_phone character varying DEFAULT NULL::character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_db_role_name VARCHAR(100);
    v_position_lower VARCHAR(50) := LOWER(p_position);
    v_db_username VARCHAR(100) := p_email; -- Ustawienie loginu DB na email
BEGIN
    -- 1. Walidacja adresu email jako loginu
    IF v_db_username IS NULL OR v_db_username = '' THEN
        RAISE EXCEPTION 'Adres email nie może być pusty, ponieważ jest używany jako login bazy danych.';
    END IF;

    -- 2. Automatyczne mapowanie Position (z employees) na rolę bazy danych
    IF v_position_lower LIKE '%receptionist%' THEN
        v_db_role_name := 'role_receptionist';
    ELSIF v_position_lower LIKE '%manager%' THEN
        v_db_role_name := 'role_manager';
    ELSIF v_position_lower LIKE '%accountant%' THEN
        v_db_role_name := 'role_accountant';
    ELSIF v_position_lower LIKE '%cleaning%' THEN
        v_db_role_name := 'role_cleaning';
    ELSE
        RAISE EXCEPTION 'Nie można przypisać pozycji "%" do żadnej z ról bazy danych. Użytkownik nie został utworzony.', p_position;
    END IF;

    -- 3. Tworzenie użytkownika bazy danych (rola)
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', v_db_username, p_password);

    -- 4. Nadanie odpowiedniej roli (uprawnień)
    EXECUTE format('GRANT %I TO %I', v_db_role_name, v_db_username);

    -- 4.1 Ustawienie search_path dla nowego użytkownika (FIX: relation does not exist)
    EXECUTE format('ALTER ROLE %I SET search_path TO public', v_db_username);

    -- 5. Dodanie pracownika do tabeli employees
    INSERT INTO public.employees (
        first_name,
        last_name,
        position,
        phone,
        email,
        hire_date
    ) VALUES (
        p_first_name,
        p_last_name,
        p_position,
        p_phone,
        p_email,
        p_hire_date
    );

    RAISE NOTICE 'Utworzono nowego użytkownika DB: % z rolą DB: % (Pozycja: %)',
        v_db_username, v_db_role_name, p_position;

EXCEPTION
    WHEN duplicate_object THEN
        RAISE EXCEPTION 'Użytkownik bazy danych/email % już istnieje.', v_db_username;
    WHEN others THEN
        RAISE EXCEPTION 'Błąd podczas tworzenia użytkownika/pracownika: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.create_db_user_and_employee(IN p_password text, IN p_first_name character varying, IN p_last_name character varying, IN p_position character varying, IN p_hire_date date, IN p_email character varying, IN p_phone character varying) OWNER TO postgres;

--
-- Name: create_reservation(date, date, integer, integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_reservation(IN p_check_in_date date, IN p_check_out_date date, IN p_guest_id integer, IN p_room_id integer, IN p_employee_id integer DEFAULT NULL::integer, IN p_number_of_guests integer DEFAULT 1)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nights INTEGER;
    v_price_per_night NUMERIC(10,2);
    v_total_cost NUMERIC(10,2);
    v_room_status VARCHAR(20);
    v_discount NUMERIC(3,2);
    v_discount_percent INTEGER;
BEGIN
    -- Sprawdzenie dostępności pokoju w podanym terminie
    PERFORM 1
    FROM reservations r
    WHERE r.room_id = p_room_id
      AND r.reservation_status IN ('confirmed', 'checked_in')
      AND (p_check_in_date < r.check_out_date AND p_check_out_date > r.check_in_date);

    IF FOUND THEN
        RAISE EXCEPTION 'Pokój % jest już zarezerwowany w podanym terminie', p_room_id;
    END IF;

    -- Pobranie ceny za noc i statusu pokoju
    SELECT price_per_night, status
    INTO v_price_per_night, v_room_status
    FROM rooms
    WHERE room_id = p_room_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pokój o ID % nie istnieje', p_room_id;
    END IF;

    IF v_room_status != 'free' AND v_room_status != 'cleaning' THEN
        RAISE EXCEPTION 'Pokój % nie jest dostępny (status: %)', p_room_id, v_room_status;
    END IF;

    -- Obliczenie liczby nocy
    v_nights := p_check_out_date - p_check_in_date;
    IF v_nights <= 0 THEN
        RAISE EXCEPTION 'Data wymeldowania musi być późniejsza niż data zameldowania';
    END IF;

    -- System lojalnościowy - pobranie rabatu dla gościa
    v_discount := get_guest_loyalty_discount(p_guest_id);
    v_discount_percent := (v_discount * 100)::INTEGER;

    -- Obliczenie kosztu z uwzględnieniem rabatu
    v_total_cost := ROUND(v_nights * v_price_per_night * (1 - v_discount), 2);

    -- Wstawienie rezerwacji
    INSERT INTO reservations (
        check_in_date, check_out_date, total_cost,
        reservation_status, guest_id, room_id, check_in_employee_id, number_of_guests
    ) VALUES (
        p_check_in_date, p_check_out_date, v_total_cost,
        'confirmed', p_guest_id, p_room_id, p_employee_id, p_number_of_guests
    );

    -- Opcjonalnie: zmiana statusu pokoju na "reserved" (jeśli chcesz taki status)
    -- UPDATE rooms SET status = 'reserved' WHERE room_id = p_room_id;

    IF v_discount_percent > 0 THEN
        RAISE NOTICE 'Rezerwacja utworzona pomyślnie. Koszt: % PLN za % nocy (rabat lojalnościowy: %)', v_total_cost, v_nights, v_discount_percent || '%';
    ELSE
        RAISE NOTICE 'Rezerwacja utworzona pomyślnie. Koszt: % PLN za % nocy', v_total_cost, v_nights;
    END IF;
END;
$$;


ALTER PROCEDURE public.create_reservation(IN p_check_in_date date, IN p_check_out_date date, IN p_guest_id integer, IN p_room_id integer, IN p_employee_id integer, IN p_number_of_guests integer) OWNER TO postgres;

--
-- Name: delete_db_role(text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.delete_db_role(IN p_role_name text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Basic safety check: Prevent deleting critical roles
    IF p_role_name IN ('postgres', 'admin', 'role_manager', 'role_receptionist', 'role_cleaning', 'role_accounting') THEN
        RAISE EXCEPTION 'Cannot delete system role: %', p_role_name;
    END IF;

    -- Dynamic SQL to drop the role. 
    -- quote_ident ensures the role name is properly escaped to prevent SQL injection.
    EXECUTE format('DROP ROLE IF EXISTS %I', p_role_name);
END;
$$;


ALTER PROCEDURE public.delete_db_role(IN p_role_name text) OWNER TO postgres;

--
-- Name: get_guest_loyalty_discount(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_guest_loyalty_discount(p_guest_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_past_stays INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_past_stays
    FROM reservations
    WHERE guest_id = p_guest_id
      AND reservation_status = 'checked_out'
      AND check_out_date < CURRENT_DATE;  -- tylko zakończone pobyty

    RETURN CASE
        WHEN v_past_stays >= 10 THEN 0.15
        WHEN v_past_stays >= 5  THEN 0.10
        WHEN v_past_stays >= 2  THEN 0.05
        ELSE 0.00
    END;
END;
$$;


ALTER FUNCTION public.get_guest_loyalty_discount(p_guest_id integer) OWNER TO postgres;

--
-- Name: get_room_availability(integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_room_availability(p_room_id integer, p_check_in_date date, p_check_out_date date) RETURNS boolean
    LANGUAGE sql
    AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM reservations r
        WHERE r.room_id = p_room_id
          AND r.reservation_status IN ('confirmed', 'checked_in')
          AND p_check_in_date < r.check_out_date
          AND p_check_out_date > r.check_in_date
    );
$$;


ALTER FUNCTION public.get_room_availability(p_room_id integer, p_check_in_date date, p_check_out_date date) OWNER TO postgres;

--
-- Name: process_payment(integer, numeric, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.process_payment(IN p_reservation_id integer, IN p_amount numeric, IN p_payment_method character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_total NUMERIC(10,2);
    v_res_status VARCHAR(20);
BEGIN
    SELECT total_cost, reservation_status
    INTO v_current_total, v_res_status
    FROM reservations
    WHERE reservation_id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rezerwacja % nie istnieje', p_reservation_id;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Kwota płatności musi być większa od zera';
    END IF;

    -- Wstawienie płatności
    INSERT INTO payments (
        reservation_id, amount, payment_date, payment_method
    ) VALUES (
        p_reservation_id, p_amount, CURRENT_DATE, p_payment_method
    );

    RAISE NOTICE 'Zarejestrowano płatność % PLN metodą: %', p_amount, p_payment_method;

    -- Opcjonalnie: automatyczne zamknięcie należności jeśli zapłacono całość
    IF (SELECT SUM(amount) FROM payments WHERE reservation_id = p_reservation_id) >= v_current_total THEN
        RAISE NOTICE 'Rezerwacja % w pełni opłacona!', p_reservation_id;
    END IF;
END;
$$;


ALTER PROCEDURE public.process_payment(IN p_reservation_id integer, IN p_amount numeric, IN p_payment_method character varying) OWNER TO postgres;

--
-- Name: room_cleaned(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.room_cleaned(IN p_room_id integer)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    UPDATE rooms SET status = 'free' WHERE room_id = p_room_id AND status = 'cleaning';
       IF NOT FOUND THEN
        RAISE EXCEPTION 'Pokój % nie jest w statusie sprzątania lub nie istnieje', p_room_id;
    END IF;
    RAISE NOTICE 'Pokój % oznaczony jako wolny', p_room_id;
END;
$$;


ALTER PROCEDURE public.room_cleaned(IN p_room_id integer) OWNER TO postgres;

--
-- Name: trg_func_calculate_reservation_cost(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_calculate_reservation_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nights INTEGER;
    v_price_per_night NUMERIC(10,2);
BEGIN
    -- Pobranie ceny za noc
    SELECT price_per_night INTO v_price_per_night
    FROM rooms WHERE room_id = NEW.room_id;

    v_nights := NEW.check_out_date - NEW.check_in_date;

    IF v_nights <= 0 THEN
        RAISE EXCEPTION 'Data wymeldowania musi być późniejsza niż zameldowania';
    END IF;

    NEW.total_cost := ROUND(v_price_per_night * v_nights, 2);

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_calculate_reservation_cost() OWNER TO postgres;

--
-- Name: trg_func_prevent_overlapping_reservations(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_prevent_overlapping_reservations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM reservations r
        WHERE r.room_id = NEW.room_id
          AND r.reservation_id <> NEW.reservation_id  -- pomija samego siebie przy UPDATE
          AND r.reservation_status IN ('confirmed', 'checked_in')
          AND NEW.check_in_date < r.check_out_date
          AND NEW.check_out_date > r.check_in_date
    ) THEN
        RAISE EXCEPTION 'Pokój % jest już zarezerwowany w terminie % – %',
            NEW.room_id, NEW.check_in_date, NEW.check_out_date;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_prevent_overlapping_reservations() OWNER TO postgres;

--
-- Name: trg_func_update_room_status_on_checkin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_update_room_status_on_checkin() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Zameldowanie = zmiana statusu rezerwacji na 'checked_in'
    IF NEW.reservation_status = 'checked_in'
       AND (OLD.reservation_status IS DISTINCT FROM 'checked_in') THEN

        UPDATE rooms
        SET status = 'occupied'
        WHERE room_id = NEW.room_id;

        RAISE NOTICE 'Pokój % zajęty po zameldowaniu (rezerwacja %)', NEW.room_id, NEW.reservation_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_update_room_status_on_checkin() OWNER TO postgres;

--
-- Name: trg_func_update_room_status_on_checkout(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_update_room_status_on_checkout() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.reservation_status = 'checked_out'
       AND OLD.reservation_status <> 'checked_out' THEN

        UPDATE rooms
        SET status = 'cleaning'
        WHERE room_id = NEW.room_id;

        RAISE NOTICE 'Pokój % wymaga sprzątania po wymeldowaniu (rezerwacja %)', NEW.room_id, NEW.reservation_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_update_room_status_on_checkout() OWNER TO postgres;

--
-- Name: trg_func_update_service_order_total(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_update_service_order_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_price NUMERIC(10,2);
BEGIN
    SELECT price INTO v_price
    FROM services WHERE service_id = NEW.service_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usługa o ID % nie istnieje', NEW.service_id;
    END IF;

    NEW.total_cost := ROUND(v_price * NEW.quantity, 2);

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_update_service_order_total() OWNER TO postgres;

--
-- Name: trg_func_validate_guest_capacity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_func_validate_guest_capacity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_capacity INTEGER;
BEGIN
    -- Domyślnie zakładamy 1 gościa jeśli kolumna nie istnieje – zabezpieczenie
    IF NEW.number_of_guests IS NULL THEN
        NEW.number_of_guests := 1;
    END IF;

    SELECT capacity INTO v_capacity
    FROM rooms WHERE room_id = NEW.room_id;

    IF NEW.number_of_guests > v_capacity THEN
        RAISE EXCEPTION 'Liczba gości (%) przekracza pojemność pokoju % (%)',
            NEW.number_of_guests, NEW.room_id, v_capacity;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_func_validate_guest_capacity() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: employees; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employees (
    employee_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    "position" character varying(50) NOT NULL,
    phone character varying(20),
    email character varying(100),
    hire_date date NOT NULL,
    CONSTRAINT check_email_format CHECK (((email)::text ~* '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'::text)),
    CONSTRAINT check_hire_date CHECK ((hire_date <= CURRENT_DATE)),
    CONSTRAINT check_phone_format CHECK (((phone)::text ~ '^[0-9]+$'::text))
);


ALTER TABLE public.employees OWNER TO postgres;

--
-- Name: Employees_EmployeeID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Employees_EmployeeID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Employees_EmployeeID_seq" OWNER TO postgres;

--
-- Name: Employees_EmployeeID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Employees_EmployeeID_seq" OWNED BY public.employees.employee_id;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payments (
    payment_id integer NOT NULL,
    reservation_id integer NOT NULL,
    amount numeric(10,2) NOT NULL,
    payment_date date NOT NULL,
    payment_method character varying(20) NOT NULL,
    CONSTRAINT check_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT check_payment_date CHECK ((payment_date <= CURRENT_DATE)),
    CONSTRAINT check_payment_method CHECK (((payment_method)::text = ANY (ARRAY[('card'::character varying)::text, ('bank_transfer'::character varying)::text, ('cash'::character varying)::text, ('blik'::character varying)::text])))
);


ALTER TABLE public.payments OWNER TO postgres;

--
-- Name: Payments_PaymentID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Payments_PaymentID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Payments_PaymentID_seq" OWNER TO postgres;

--
-- Name: Payments_PaymentID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Payments_PaymentID_seq" OWNED BY public.payments.payment_id;


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rooms (
    room_id integer NOT NULL,
    room_number character varying(10) NOT NULL,
    room_type character varying(20) NOT NULL,
    price_per_night numeric(10,2) NOT NULL,
    status character varying(20) NOT NULL,
    capacity integer NOT NULL,
    CONSTRAINT check_capacity_positive CHECK ((capacity > 0)),
    CONSTRAINT valid_room_status CHECK (((status)::text = ANY (ARRAY[('free'::character varying)::text, ('cleaning'::character varying)::text, ('occupied'::character varying)::text, ('reserved'::character varying)::text, ('maintenance'::character varying)::text])))
);


ALTER TABLE public.rooms OWNER TO postgres;

--
-- Name: Rooms_RoomID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Rooms_RoomID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Rooms_RoomID_seq" OWNER TO postgres;

--
-- Name: Rooms_RoomID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Rooms_RoomID_seq" OWNED BY public.rooms.room_id;


--
-- Name: service_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.service_orders (
    order_id integer NOT NULL,
    reservation_id integer NOT NULL,
    service_id integer NOT NULL,
    order_date date NOT NULL,
    quantity integer NOT NULL,
    total_cost numeric NOT NULL,
    service_employee integer,
    CONSTRAINT check_order_date CHECK ((order_date <= CURRENT_DATE)),
    CONSTRAINT check_quantity_positive CHECK ((quantity > 0)),
    CONSTRAINT check_total_cost_non_negative CHECK ((total_cost >= (0)::numeric))
);


ALTER TABLE public.service_orders OWNER TO postgres;

--
-- Name: ServiceOrders_OrderID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."ServiceOrders_OrderID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."ServiceOrders_OrderID_seq" OWNER TO postgres;

--
-- Name: ServiceOrders_OrderID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."ServiceOrders_OrderID_seq" OWNED BY public.service_orders.order_id;


--
-- Name: services; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.services (
    service_id integer NOT NULL,
    service_name character varying(100) NOT NULL,
    price numeric(10,2) NOT NULL,
    description text,
    CONSTRAINT check_price_positive CHECK ((price > (0)::numeric))
);


ALTER TABLE public.services OWNER TO postgres;

--
-- Name: Services_ServiceID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Services_ServiceID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Services_ServiceID_seq" OWNER TO postgres;

--
-- Name: Services_ServiceID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Services_ServiceID_seq" OWNED BY public.services.service_id;


--
-- Name: guests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.guests (
    guest_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    email character varying(100),
    phone character varying(20),
    address character varying(200),
    id_number character varying(20),
    date_of_birth date,
    nationality character varying(50),
    gender character varying(10),
    CONSTRAINT check_date_of_birth CHECK ((date_of_birth <= CURRENT_DATE)),
    CONSTRAINT check_email_format CHECK (((email)::text ~* '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'::text)),
    CONSTRAINT check_gender CHECK (((gender)::text = ANY (ARRAY[('male'::character varying)::text, ('female'::character varying)::text]))),
    CONSTRAINT check_phone_format CHECK (((phone)::text ~ '^[0-9]+$'::text))
);


ALTER TABLE public.guests OWNER TO postgres;

--
-- Name: guests_guestid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.guests_guestid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.guests_guestid_seq OWNER TO postgres;

--
-- Name: guests_guestid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.guests_guestid_seq OWNED BY public.guests.guest_id;


--
-- Name: reservations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservations (
    reservation_id integer NOT NULL,
    check_in_date date NOT NULL,
    check_out_date date NOT NULL,
    total_cost numeric(10,2) NOT NULL,
    reservation_status character varying(20) NOT NULL,
    guest_id integer NOT NULL,
    room_id integer NOT NULL,
    check_in_employee_id integer,
    number_of_guests integer DEFAULT 1,
    CONSTRAINT check_cost CHECK ((total_cost >= (0)::numeric)),
    CONSTRAINT check_dates CHECK ((check_out_date > check_in_date)),
    CONSTRAINT check_number_of_guests CHECK ((number_of_guests > 0)),
    CONSTRAINT check_reservation_status CHECK (((reservation_status)::text = ANY (ARRAY[('checked_in'::character varying)::text, ('checked_out'::character varying)::text, ('confirmed'::character varying)::text, ('cancelled'::character varying)::text])))
);


ALTER TABLE public.reservations OWNER TO postgres;



--
-- Name: reservations_ReservationID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."reservations_ReservationID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."reservations_ReservationID_seq" OWNER TO postgres;

--
-- Name: reservations_ReservationID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."reservations_ReservationID_seq" OWNED BY public.reservations.reservation_id;


--
-- Name: view_all_reservations; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_all_reservations AS
 SELECT r.reservation_id,
    r.guest_id,
    (((g.first_name)::text || ' '::text) || (g.last_name)::text) AS guest_name,
    ro.room_number,
    r.check_in_date,
    r.check_out_date,
    r.reservation_status,
    r.total_cost,
    r.number_of_guests
   FROM ((public.reservations r
     JOIN public.guests g ON ((r.guest_id = g.guest_id)))
     JOIN public.rooms ro ON ((r.room_id = ro.room_id)))
  ORDER BY r.check_in_date DESC;


ALTER VIEW public.view_all_reservations OWNER TO postgres;

--
-- Name: view_current_reservations; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_current_reservations AS
 SELECT r.reservation_id,
    r.guest_id,
    (((g.first_name)::text || ' '::text) || (g.last_name)::text) AS guest_name,
    ro.room_number,
    r.check_in_date,
    r.check_out_date,
    r.reservation_status,
    r.total_cost,
    r.number_of_guests
   FROM ((public.reservations r
     JOIN public.guests g ON ((r.guest_id = g.guest_id)))
     JOIN public.rooms ro ON ((r.room_id = ro.room_id)))
  WHERE (((r.reservation_status)::text = 'checked_in'::text) OR ((r.reservation_status)::text = 'confirmed'::text))
  ORDER BY r.check_in_date DESC;


ALTER VIEW public.view_current_reservations OWNER TO postgres;

--
-- Name: view_free_rooms; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_free_rooms AS
 SELECT room_id,
    room_number,
    room_type,
    price_per_night,
    capacity,
    status
   FROM public.rooms
  WHERE ((status)::text = 'free'::text);


ALTER VIEW public.view_free_rooms OWNER TO postgres;

--
-- Name: view_guest_history; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_guest_history AS
SELECT
    NULL::integer AS guest_id,
    NULL::character varying(50) AS first_name,
    NULL::character varying(50) AS last_name,
    NULL::bigint AS total_stays,
    NULL::numeric AS total_spent;


ALTER VIEW public.view_guest_history OWNER TO postgres;

--
-- Name: view_hotel_occupancy; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_hotel_occupancy AS
 SELECT count(*) FILTER (WHERE ((status)::text = 'occupied'::text)) AS occupied_rooms,
    count(*) AS total_rooms,
        CASE
            WHEN (count(*) = 0) THEN (0)::numeric
            ELSE round((((count(*) FILTER (WHERE ((status)::text = 'occupied'::text)))::numeric / (count(*))::numeric) * (100)::numeric), 2)
        END AS occupancy_percentage
   FROM public.rooms;


ALTER VIEW public.view_hotel_occupancy OWNER TO postgres;

--
-- Name: view_revenue_report; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_revenue_report AS
 SELECT (EXTRACT(month FROM payment_date))::integer AS month,
    (EXTRACT(year FROM payment_date))::integer AS year,
    sum(amount) AS total_revenue
   FROM public.payments
  GROUP BY (EXTRACT(year FROM payment_date)), (EXTRACT(month FROM payment_date))
  ORDER BY (EXTRACT(year FROM payment_date)) DESC, (EXTRACT(month FROM payment_date)) DESC;


ALTER VIEW public.view_revenue_report OWNER TO postgres;

--
-- Name: view_upcoming_checkouts; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_upcoming_checkouts AS
 SELECT reservations.reservation_id,
    guests.first_name,
    guests.last_name,
    rooms.room_number,
    reservations.check_out_date
   FROM ((public.reservations
     JOIN public.guests ON ((reservations.guest_id = guests.guest_id)))
     JOIN public.rooms ON ((reservations.room_id = rooms.room_id)))
  WHERE ((reservations.check_out_date >= CURRENT_DATE) AND (reservations.check_out_date <= (CURRENT_DATE + '3 days'::interval)) AND ((reservations.reservation_status)::text = 'checked_in'::text));


ALTER VIEW public.view_upcoming_checkouts OWNER TO postgres;

--
-- Name: employees employee_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN employee_id SET DEFAULT nextval('public."Employees_EmployeeID_seq"'::regclass);


--
-- Name: guests guest_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests ALTER COLUMN guest_id SET DEFAULT nextval('public.guests_guestid_seq'::regclass);


--
-- Name: payments payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments ALTER COLUMN payment_id SET DEFAULT nextval('public."Payments_PaymentID_seq"'::regclass);


--
-- Name: reservations reservation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations ALTER COLUMN reservation_id SET DEFAULT nextval('public."reservations_ReservationID_seq"'::regclass);


--
-- Name: rooms room_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms ALTER COLUMN room_id SET DEFAULT nextval('public."Rooms_RoomID_seq"'::regclass);


--
-- Name: service_orders order_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders ALTER COLUMN order_id SET DEFAULT nextval('public."ServiceOrders_OrderID_seq"'::regclass);


--
-- Name: services service_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.services ALTER COLUMN service_id SET DEFAULT nextval('public."Services_ServiceID_seq"'::regclass);




--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employees (employee_id, first_name, last_name, "position", phone, email, hire_date) FROM stdin;
1	Admin	System	manager	000000000	admin@hotel.com	2025-12-21
2	Anna	Kowalska	receptionist	432859203	receptionist@hotel.com	2025-12-21
3	Piotr	Nowak	accountant	932539203	accountant@hotel.com	2025-12-21
4	Szymon	Szymczak	cleaning	483258394	cleaning@hotel.com	2025-12-21
5	Readonly	System	readonly	000000000	readonly@hotel.com	2025-12-21
\.


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

--
-- Data for Name: guests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.guests (guest_id, first_name, last_name, email, phone, address, id_number, date_of_birth, nationality, gender) FROM stdin;
1	Janelle	Binestead	jbinestead0@yahoo.co.jp	9992355298	22-222 Gdańsk	VWO639993	1970-02-17	Australian	female
2	Vikky	Bilton	vbilton1@about.me	5849825484	11-111 Kraków	MFF718049	1997-07-07	Japanese	male
3	Johnath	Shovelin	jshovelin2@google.cn	6207649339	44-444 Poznań	OJO934467	1967-01-27	Canadian	female
4	Bartholomew	McCambrois	bmccambrois3@joomla.org	1571505891	al. Słoneczna 3	ODW155764	1986-11-06	German	female
5	Pauly	MacCaull	pmaccaull4@wunderground.com	6707329498	pl. Zielony 2	AJQ044620	1964-08-03	Canadian	male
6	Lethia	Townshend	ltownshend5@yahoo.com	1404950895	pl. Zielony 2	ZHU922108	1975-12-10	Japanese	female
7	Bendick	McCullogh	bmccullogh6@ox.ac.uk	2791377771	44-444 Poznań	UCH335578	1965-12-06	German	female
8	Loella	Bernhardt	lbernhardt7@amazon.de	7969673898	00-001 Warszawa	HHX218999	1997-05-18	American	female
9	Gery	Uff	guff8@qq.com	3473346111	pl. Zielony 2	PVR878645	2003-09-19	American	female
10	Darla	Molder	dmolder9@fda.gov	3712947757	33-333 Wrocław	VON703925	2002-05-01	American	female
11	Christin	Desorts	cdesortsa@state.gov	6955472078	pl. Kwiatowy 10	VLE594790	1984-03-29	Canadian	male
12	Eddi	Hebditch	ehebditchb@lycos.com	4853016294	ul. Morska 7	ZFS073341	2005-11-26	Canadian	female
13	Rickie	Cavee	rcaveec@noaa.gov	8094651418	11-111 Kraków	ZIP935284	1963-09-11	Japanese	female
14	Fee	Blaydon	fblaydond@altervista.org	3704090813	33-333 Wrocław	HGS857560	1993-07-28	Japanese	male
15	Joshia	Cork	jcorke@miibeian.gov.cn	5972964022	11-111 Kraków	AUY870356	1972-06-07	Australian	female
16	Bradley	Jilkes	bjilkesf@taobao.com	6196349082	00-001 Warszawa	EOD960374	1980-10-07	Mexican	female
17	Davy	Deinert	ddeinertg@bluehost.com	5124647838	44-444 Poznań	UBL527098	1972-11-11	Australian	male
18	Easter	Huge	ehugeh@privacy.gov.au	3872523348	22-222 Gdańsk	GHB263051	1977-07-07	American	male
19	Dominick	Ormiston	dormistoni@ameblo.jp	5166938249	ul. Morska 7	FDM775165	1971-03-07	German	female
20	Mead	Birchenhead	mbirchenheadj@webnode.com	1406698070	00-001 Warszawa	XOK462743	2001-02-21	American	male
21	Effie	Haley	ehaleyk@comsenz.com	6831176173	al. Słoneczna 3	WCX823144	2005-10-27	American	male
22	Prudi	Fellon	pfellonl@amazonaws.com	6995625981	00-001 Warszawa	IBK256701	1982-11-28	American	male
23	Munmro	Rumford	mrumfordm@msn.com	4323931072	11-111 Kraków	QTZ815946	1961-08-09	Australian	male
24	Sergio	Jedrzejewsky	sjedrzejewskyn@google.com.hk	8332481686	al. Słoneczna 3	HVO889280	1996-11-21	Canadian	female
25	Anastassia	Keling	akelingo@disqus.com	3897759060	11-111 Kraków	OYE228944	1994-12-17	German	female
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payments (payment_id, reservation_id, amount, payment_date, payment_method) FROM stdin;
1	1	1800.00	2025-01-10	card
2	2	690.00	2025-01-15	cash
3	3	1800.00	2025-01-25	bank_transfer
4	4	1050.00	2025-02-04	blik
5	5	1040.00	2025-02-12	card
6	6	1500.00	2025-02-17	cash
7	7	1800.00	2025-03-05	card
8	8	3150.00	2025-03-15	bank_transfer
9	9	700.00	2025-03-22	blik
10	10	1150.00	2025-04-10	card
11	11	1200.00	2025-04-18	cash
12	12	1880.00	2025-04-30	card
13	13	1650.00	2025-05-04	bank_transfer
14	14	1750.00	2025-05-15	blik
15	15	1600.00	2025-05-25	card
16	16	2100.00	2025-06-07	cash
17	17	2880.00	2025-06-15	card
18	18	2000.00	2025-06-25	bank_transfer
19	19	3550.00	2025-07-10	card
20	20	1700.00	2025-07-20	blik
21	21	2200.00	2025-08-05	card
22	22	1750.00	2025-08-15	cash
23	23	1150.00	2025-08-25	card
24	24	1700.00	2025-09-10	bank_transfer
25	25	3070.00	2025-09-20	card
26	26	1400.00	2025-10-05	blik
27	27	2250.00	2025-10-15	card
28	28	1400.00	2025-11-05	cash
29	29	1750.00	2025-11-20	bank_transfer
30	30	1600.00	2025-12-06	card
31	45	1820.00	2025-12-21	cash
\.


--
-- Data for Name: reservations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservations (reservation_id, check_in_date, check_out_date, total_cost, reservation_status, guest_id, room_id, check_in_employee_id, number_of_guests) FROM stdin;
1	2025-01-05	2025-01-10	1500.00	checked_out	1	1	2	2
2	2025-01-12	2025-01-15	690.00	checked_out	2	3	2	1
3	2025-01-20	2025-01-25	1700.00	checked_out	3	4	2	3
4	2025-02-01	2025-02-04	1050.00	checked_out	4	6	2	2
5	2025-02-10	2025-02-12	800.00	checked_out	5	7	2	2
6	2025-02-14	2025-02-17	1500.00	checked_out	6	9	2	2
7	2025-03-01	2025-03-05	1800.00	checked_out	7	10	2	2
8	2025-03-10	2025-03-15	2750.00	checked_out	8	11	2	4
9	2025-03-20	2025-03-22	700.00	checked_out	9	12	2	2
10	2025-04-05	2025-04-10	1150.00	checked_out	10	3	2	2
11	2025-04-15	2025-04-18	1200.00	checked_out	11	7	2	1
12	2025-04-25	2025-04-30	1750.00	checked_out	12	15	2	2
13	2025-05-01	2025-05-04	1650.00	checked_out	13	11	2	3
14	2025-05-10	2025-05-15	1750.00	checked_out	14	13	2	2
15	2025-05-20	2025-05-25	1500.00	checked_out	15	1	2	2
16	2025-06-01	2025-06-07	2100.00	checked_out	16	12	2	4
17	2025-06-10	2025-06-15	2500.00	checked_out	17	9	2	2
18	2025-06-20	2025-06-25	2000.00	checked_out	18	7	2	3
19	2025-07-01	2025-07-10	2700.00	checked_out	19	1	2	2
20	2025-07-15	2025-07-20	1700.00	checked_out	20	16	2	2
21	2025-08-01	2025-08-05	2200.00	checked_out	21	11	2	2
22	2025-08-10	2025-08-15	1750.00	checked_out	22	12	2	4
23	2025-08-20	2025-08-25	1150.00	checked_out	23	3	2	2
24	2025-09-05	2025-09-10	1750.00	checked_out	24	15	2	2
25	2025-09-15	2025-09-20	2750.00	checked_out	25	11	2	3
26	2025-10-01	2025-10-05	1360.00	checked_out	1	16	2	2
27	2025-10-10	2025-10-15	2250.00	checked_out	2	10	2	2
28	2025-11-01	2025-11-05	1360.00	checked_out	3	4	2	2
29	2025-11-15	2025-11-20	1750.00	checked_out	4	13	2	2
30	2025-12-01	2025-12-06	1500.00	checked_out	5	1	2	2
31	2025-12-15	2025-12-20	2500.00	checked_out	6	9	2	2
40	2026-01-15	2026-01-20	2500.00	confirmed	3	9	2	2
41	2026-01-22	2026-01-25	1650.00	confirmed	22	11	2	3
42	2026-01-25	2026-01-28	690.00	confirmed	1	3	2	1
43	2026-01-29	2026-02-02	1360.00	confirmed	10	4	2	2
46	2025-12-22	2025-12-24	460.00	confirmed	14	5	2	1
47	2025-12-24	2025-12-27	1350.00	confirmed	18	10	2	2
48	2025-12-26	2025-12-29	690.00	confirmed	20	3	2	2
49	2025-12-27	2025-12-30	1050.00	confirmed	25	12	2	4
45	2025-12-21	2025-12-26	1820.00	checked_in	11	4	1	2
\.


--
-- Data for Name: rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rooms (room_id, room_number, room_type, price_per_night, status, capacity) FROM stdin;
1	001	suite	300.00	free	2
3	002	standard	230.00	free	4
5	004	standard	230.00	free	4
6	005	standard	350.00	free	6
7	101	apartment	400.00	free	3
8	102	apartment	350.00	free	4
10	104	suite	450.00	free	5
11	105	suite	550.00	free	5
12	201	standard	350.00	free	6
13	202	standard	350.00	free	4
14	203	standard	230.00	free	2
15	204	apartment	350.00	free	4
16	205	apartment	340.00	free	4
9	103	suite	500.00	cleaning	5
4	003	apartment	340.00	occupied	4
\.


--
-- Data for Name: service_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.service_orders (order_id, reservation_id, service_id, order_date, quantity, total_cost, service_employee) FROM stdin;
1	1	1	2025-01-06	2	110.00	4
2	1	2	2025-01-07	1	190.00	4
3	3	10	2025-01-20	1	100.00	2
4	5	4	2025-02-11	2	240.00	4
5	8	8	2025-03-12	2	400.00	4
6	12	5	2025-04-26	2	130.00	4
7	15	10	2025-05-20	1	100.00	2
8	17	2	2025-06-11	2	380.00	4
9	19	1	2025-07-02	10	550.00	4
10	25	6	2025-09-16	2	320.00	4
11	30	10	2025-12-01	1	100.00	2
12	45	4	2025-12-21	1	120.00	1
\.


--
-- Data for Name: services; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.services (service_id, service_name, price, description) FROM stdin;
2	Masaż relaksacyjny	190.00	Profesjonalny masaż relaksacyjny wykonywany przez doświadczonego terapeutę
3	Sesja fitness	160.00	Indywidualna lub grupowa sesja fitness pod okiem wykwalifikowanego trenera
4	Basen	120.00	Nieograniczony dostęp do hotelowego basenu rekreacyjnego
1	Obiad	55.00	Dodatkowa opcja obiadu w hotelu
5	Wypożyczenie roweru	65.00	Wypożyczenie roweru na cały dzień
6	Seans w saunie	160.00	Relaksujący seans w saunie suchej lub parowej
7	Lekcja jogi	135.00	Indywidualna lub grupowa lekcja jogi prowadzona przez certyfikowanego instruktora
8	Degustacja win	200.00	Ekskluzywna degustacja wybranych win z sommelierem
9	Sesja medytacji	150.00	Guidowana sesja medytacji w spokojnej atmosferze
10	Zestaw powitalny	100.00	Specjalny zestaw powitalny przygotowany na przybycie. Obejmuje świeże owoce, butelkę wina lub szampana, słodycze oraz drobne upominki
\.


--
-- Name: Employees_EmployeeID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Employees_EmployeeID_seq"', 5, true);


--
-- Name: Payments_PaymentID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Payments_PaymentID_seq"', 31, true);


--
-- Name: Rooms_RoomID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Rooms_RoomID_seq"', 16, true);


--
-- Name: ServiceOrders_OrderID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."ServiceOrders_OrderID_seq"', 12, true);


--
-- Name: Services_ServiceID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Services_ServiceID_seq"', 10, true);


--
-- Name: guests_guestid_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.guests_guestid_seq', 1, false);


--
-- Name: reservations_ReservationID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."reservations_ReservationID_seq"', 49, true);


--
-- Name: employees Employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT "Employees_pkey" PRIMARY KEY (employee_id);


--
-- Name: payments Payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT "Payments_pkey" PRIMARY KEY (payment_id);


--
-- Name: rooms Rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT "Rooms_pkey" PRIMARY KEY (room_id);


--
-- Name: service_orders ServiceOrders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT "ServiceOrders_pkey" PRIMARY KEY (order_id);


--
-- Name: services Services_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT "Services_pkey" PRIMARY KEY (service_id);


--
-- Name: rooms check_room_type; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.rooms
    ADD CONSTRAINT check_room_type CHECK (((room_type)::text = ANY (ARRAY[('standard'::character varying)::text, ('apartment'::character varying)::text, ('suite'::character varying)::text]))) NOT VALID;


--
-- Name: guests guests_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests
    ADD CONSTRAINT guests_email_key UNIQUE (email);


--
-- Name: guests guests_idnumber_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests
    ADD CONSTRAINT guests_idnumber_key UNIQUE (id_number);


--
-- Name: guests guests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests
    ADD CONSTRAINT guests_pkey PRIMARY KEY (guest_id);


--
-- Name: reservations reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (reservation_id);


--
-- Name: rooms unique_room_number; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT unique_room_number UNIQUE (room_number);


--
-- Name: idx_guests_nationality; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_guests_nationality ON public.guests USING btree (nationality);


--
-- Name: view_guest_history _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.view_guest_history AS
 SELECT guests.guest_id,
    guests.first_name,
    guests.last_name,
    count(reservations.reservation_id) AS total_stays,
    sum(reservations.total_cost) AS total_spent
   FROM (public.guests
     LEFT JOIN public.reservations ON ((guests.guest_id = reservations.guest_id)))
  GROUP BY guests.guest_id;


--
-- Name: reservations trg_calculate_reservation_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_calculate_reservation_cost BEFORE INSERT OR UPDATE OF check_in_date, check_out_date, room_id ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.trg_func_calculate_reservation_cost();


--
-- Name: reservations trg_prevent_overlapping_reservations; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_prevent_overlapping_reservations BEFORE INSERT OR UPDATE OF check_in_date, check_out_date, room_id ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.trg_func_prevent_overlapping_reservations();


--
-- Name: reservations trg_update_room_status_on_checkin; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_room_status_on_checkin BEFORE UPDATE OF reservation_status ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.trg_func_update_room_status_on_checkin();


--
-- Name: reservations trg_update_room_status_on_checkout; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_room_status_on_checkout BEFORE UPDATE OF reservation_status ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.trg_func_update_room_status_on_checkout();


--
-- Name: service_orders trg_update_service_order_total; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_service_order_total BEFORE INSERT OR UPDATE OF service_id, quantity ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.trg_func_update_service_order_total();


--
-- Name: reservations trg_validate_guest_capacity; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validate_guest_capacity BEFORE INSERT OR UPDATE OF number_of_guests, room_id ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.trg_func_validate_guest_capacity();


--
-- Name: service_orders Reservation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT "Reservation_fkey" FOREIGN KEY (reservation_id) REFERENCES public.reservations(reservation_id);


--
-- Name: payments Reservation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT "Reservation_id_fkey" FOREIGN KEY (reservation_id) REFERENCES public.reservations(reservation_id);


--
-- Name: service_orders ServiceEmployee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT "ServiceEmployee_fkey" FOREIGN KEY (service_employee) REFERENCES public.employees(employee_id);


--
-- Name: service_orders Service_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT "Service_fkey" FOREIGN KEY (service_id) REFERENCES public.services(service_id);


--
-- Name: reservations check_in_employee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT check_in_employee_fkey FOREIGN KEY (check_in_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: reservations guest_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT guest_fkey FOREIGN KEY (guest_id) REFERENCES public.guests(guest_id);


--
-- Name: reservations room_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT room_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(room_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO role_receptionist;
GRANT ALL ON SCHEMA public TO role_manager;
GRANT USAGE ON SCHEMA public TO role_accountant;
GRANT USAGE ON SCHEMA public TO role_cleaning;
GRANT USAGE ON SCHEMA public TO role_readonly;


--
-- Name: PROCEDURE add_service_to_reservation(IN p_reservation_id integer, IN p_service_id integer, IN p_quantity integer, IN p_service_employee_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.add_service_to_reservation(IN p_reservation_id integer, IN p_service_id integer, IN p_quantity integer, IN p_service_employee_id integer) TO role_receptionist;


--
-- Name: FUNCTION calculate_reservation_cost(p_room_id integer, p_check_in_date date, p_check_out_date date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_reservation_cost(p_room_id integer, p_check_in_date date, p_check_out_date date) TO role_receptionist;
GRANT ALL ON FUNCTION public.calculate_reservation_cost(p_room_id integer, p_check_in_date date, p_check_out_date date) TO role_readonly;


--
-- Name: FUNCTION calculate_total_with_services(p_reservation_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_total_with_services(p_reservation_id integer) TO role_receptionist;
GRANT ALL ON FUNCTION public.calculate_total_with_services(p_reservation_id integer) TO role_accountant;
GRANT ALL ON FUNCTION public.calculate_total_with_services(p_reservation_id integer) TO role_readonly;


--
-- Name: PROCEDURE cancel_reservation(IN p_reservation_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.cancel_reservation(IN p_reservation_id integer) TO role_receptionist;


--
-- Name: PROCEDURE checkout(IN p_reservation_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.checkout(IN p_reservation_id integer) TO role_receptionist;


--
-- Name: PROCEDURE create_reservation(IN p_check_in_date date, IN p_check_out_date date, IN p_guest_id integer, IN p_room_id integer, IN p_employee_id integer, IN p_number_of_guests integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.create_reservation(IN p_check_in_date date, IN p_check_out_date date, IN p_guest_id integer, IN p_room_id integer, IN p_employee_id integer, IN p_number_of_guests integer) TO role_receptionist;


--
-- Name: PROCEDURE delete_db_role(IN p_role_name text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.delete_db_role(IN p_role_name text) TO role_manager;


--
-- Name: FUNCTION get_guest_loyalty_discount(p_guest_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_guest_loyalty_discount(p_guest_id integer) TO role_receptionist;
GRANT ALL ON FUNCTION public.get_guest_loyalty_discount(p_guest_id integer) TO role_readonly;


--
-- Name: FUNCTION get_room_availability(p_room_id integer, p_check_in_date date, p_check_out_date date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_room_availability(p_room_id integer, p_check_in_date date, p_check_out_date date) TO role_receptionist;
GRANT ALL ON FUNCTION public.get_room_availability(p_room_id integer, p_check_in_date date, p_check_out_date date) TO role_readonly;


--
-- Name: PROCEDURE process_payment(IN p_reservation_id integer, IN p_amount numeric, IN p_payment_method character varying); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.process_payment(IN p_reservation_id integer, IN p_amount numeric, IN p_payment_method character varying) TO role_receptionist;


--
-- Name: PROCEDURE room_cleaned(IN p_room_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.room_cleaned(IN p_room_id integer) TO role_cleaning;


--
-- Name: FUNCTION trg_func_calculate_reservation_cost(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_calculate_reservation_cost() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_calculate_reservation_cost() TO role_readonly;


--
-- Name: FUNCTION trg_func_prevent_overlapping_reservations(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_prevent_overlapping_reservations() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_prevent_overlapping_reservations() TO role_readonly;


--
-- Name: FUNCTION trg_func_update_room_status_on_checkin(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_update_room_status_on_checkin() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_update_room_status_on_checkin() TO role_readonly;


--
-- Name: FUNCTION trg_func_update_room_status_on_checkout(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_update_room_status_on_checkout() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_update_room_status_on_checkout() TO role_readonly;


--
-- Name: FUNCTION trg_func_update_service_order_total(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_update_service_order_total() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_update_service_order_total() TO role_readonly;


--
-- Name: FUNCTION trg_func_validate_guest_capacity(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_func_validate_guest_capacity() TO role_receptionist;
GRANT ALL ON FUNCTION public.trg_func_validate_guest_capacity() TO role_readonly;


--
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.employees TO role_receptionist;
GRANT ALL ON TABLE public.employees TO role_manager;
GRANT SELECT ON TABLE public.employees TO role_accountant;
GRANT SELECT ON TABLE public.employees TO role_readonly;


--
-- Name: SEQUENCE "Employees_EmployeeID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."Employees_EmployeeID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."Employees_EmployeeID_seq" TO role_manager;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO role_receptionist;
GRANT ALL ON TABLE public.payments TO role_manager;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payments TO role_accountant;
GRANT SELECT ON TABLE public.payments TO role_readonly;


--
-- Name: SEQUENCE "Payments_PaymentID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."Payments_PaymentID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."Payments_PaymentID_seq" TO role_manager;


--
-- Name: TABLE rooms; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.rooms TO role_receptionist;
GRANT ALL ON TABLE public.rooms TO role_manager;
GRANT SELECT ON TABLE public.rooms TO role_accountant;
GRANT SELECT ON TABLE public.rooms TO role_cleaning;
GRANT SELECT ON TABLE public.rooms TO role_readonly;


--
-- Name: COLUMN rooms.status; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(status) ON TABLE public.rooms TO role_cleaning;


--
-- Name: SEQUENCE "Rooms_RoomID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."Rooms_RoomID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."Rooms_RoomID_seq" TO role_manager;


--
-- Name: TABLE service_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.service_orders TO role_receptionist;
GRANT ALL ON TABLE public.service_orders TO role_manager;
GRANT SELECT ON TABLE public.service_orders TO role_accountant;
GRANT SELECT ON TABLE public.service_orders TO role_readonly;


--
-- Name: SEQUENCE "ServiceOrders_OrderID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."ServiceOrders_OrderID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."ServiceOrders_OrderID_seq" TO role_manager;


--
-- Name: TABLE services; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.services TO role_receptionist;
GRANT ALL ON TABLE public.services TO role_manager;
GRANT SELECT ON TABLE public.services TO role_accountant;
GRANT SELECT ON TABLE public.services TO role_readonly;


--
-- Name: SEQUENCE "Services_ServiceID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."Services_ServiceID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."Services_ServiceID_seq" TO role_manager;


--
-- Name: TABLE guests; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.guests TO role_receptionist;
GRANT ALL ON TABLE public.guests TO role_manager;
GRANT SELECT ON TABLE public.guests TO role_accountant;
GRANT SELECT ON TABLE public.guests TO role_readonly;
GRANT SELECT ON TABLE public.guests TO role_cleaning;


--
-- Name: SEQUENCE guests_guestid_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.guests_guestid_seq TO role_receptionist;
GRANT ALL ON SEQUENCE public.guests_guestid_seq TO role_manager;


--
-- Name: TABLE reservations; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.reservations TO role_receptionist;
GRANT ALL ON TABLE public.reservations TO role_manager;
GRANT SELECT ON TABLE public.reservations TO role_accountant;
GRANT SELECT ON TABLE public.reservations TO role_readonly;
GRANT SELECT ON TABLE public.reservations TO role_cleaning;


--
-- Name: SEQUENCE "reservations_ReservationID_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public."reservations_ReservationID_seq" TO role_receptionist;
GRANT ALL ON SEQUENCE public."reservations_ReservationID_seq" TO role_manager;


--
-- Name: TABLE view_all_reservations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.view_all_reservations TO role_manager;
GRANT SELECT ON TABLE public.view_all_reservations TO role_receptionist;


--
-- Name: TABLE view_current_reservations; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.view_current_reservations TO role_receptionist;
GRANT ALL ON TABLE public.view_current_reservations TO role_manager;
GRANT SELECT ON TABLE public.view_current_reservations TO role_accountant;
GRANT SELECT ON TABLE public.view_current_reservations TO role_readonly;


--
-- Name: TABLE view_free_rooms; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.view_free_rooms TO role_receptionist;
GRANT ALL ON TABLE public.view_free_rooms TO role_manager;
GRANT SELECT ON TABLE public.view_free_rooms TO role_accountant;
GRANT SELECT ON TABLE public.view_free_rooms TO role_readonly;


--
-- Name: TABLE view_guest_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.view_guest_history TO role_receptionist;
GRANT ALL ON TABLE public.view_guest_history TO role_manager;
GRANT SELECT ON TABLE public.view_guest_history TO role_accountant;
GRANT SELECT ON TABLE public.view_guest_history TO role_readonly;


--
-- Name: TABLE view_hotel_occupancy; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.view_hotel_occupancy TO role_accountant;
GRANT ALL ON TABLE public.view_hotel_occupancy TO role_manager;
GRANT SELECT ON TABLE public.view_hotel_occupancy TO role_readonly;
GRANT SELECT,INSERT,UPDATE ON TABLE public.view_hotel_occupancy TO role_receptionist;


--
-- Name: TABLE view_revenue_report; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.view_revenue_report TO role_receptionist;
GRANT ALL ON TABLE public.view_revenue_report TO role_manager;
GRANT SELECT ON TABLE public.view_revenue_report TO role_accountant;
GRANT SELECT ON TABLE public.view_revenue_report TO role_readonly;


--
-- Name: TABLE view_upcoming_checkouts; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.view_upcoming_checkouts TO role_receptionist;
GRANT ALL ON TABLE public.view_upcoming_checkouts TO role_manager;
GRANT SELECT ON TABLE public.view_upcoming_checkouts TO role_accountant;
GRANT SELECT ON TABLE public.view_upcoming_checkouts TO role_readonly;


--
-- PostgreSQL database dump complete
--

\unrestrict A1rmiBUBLww3kI6gN9e3tpGQZKlbtpZMZLxfUgmjEgGD8MXo83eLGqPJ5If1ZqW

