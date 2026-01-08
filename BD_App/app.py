from flask import Flask, render_template, request, redirect, url_for, flash, session, jsonify
from flask_login import (
    LoginManager,
    UserMixin,
    login_user,
    logout_user,
    login_required,
    current_user,
)
import psycopg2
import psycopg2.extras
import psycopg2.errors
from functools import wraps
from config import Config
import re
app = Flask(__name__)
app.config.from_object(Config)

login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = "login"
login_manager.login_message_category = "info"


class User(UserMixin):
    def __init__(self, username, role):
        self.id = username
        self.role = role


@login_manager.user_loader
def load_user(username):
    return User(username, session.get("role")) if username else None


def get_db_connection():
    return psycopg2.connect(
        host="localhost",
        database=Config.DATABASE["database"],
        user=session["db_user"],
        password=session["db_password"],
        port=5432,
    )


def log_sql(cur, query, params=None):
    """Formatuje i loguje wykonane zapytanie SQL do flash messages."""
    try:
        if params:
            formatted_sql = cur.mogrify(query, params).decode("utf-8")
        else:
            formatted_sql = query
        flash(formatted_sql, "sql")
    except Exception:
        flash(query, "sql")





def validate_name(name, field_name="Pole"):
    """Waliduje imię/nazwisko - tylko litery, min 2 znaki."""
    if not name or len(name.strip()) < 2:
        return False, f"{field_name} musi mieć minimum 2 znaki."
    if not re.match(r"^[A-Za-zĄąĆćĘęŁłŃńÓóŚśŹźŻż\s\-]+$", name):
        return False, f"{field_name} może zawierać tylko litery."
    return True, None


def validate_email(email):
    """Waliduje adres email."""
    if not email:
        return False, "Email jest wymagany."
    pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if not re.match(pattern, email):
        return False, "Podaj poprawny adres email."
    return True, None


def validate_phone(phone):
    """Waliduje numer telefonu (opcjonalny)."""
    if not phone:
        return True, None
    cleaned = re.sub(r"[\s\-\+]", "", phone)
    if not cleaned.isdigit() or len(cleaned) < 9 or len(cleaned) > 15:
        return False, "Numer telefonu musi mieć 9-15 cyfr."
    return True, None


def validate_id_number(id_number):
    """Waliduje numer dowodu/paszportu."""
    if not id_number:
        return False, "Numer dokumentu jest wymagany."
    if not re.match(r"^[A-Za-z0-9]{6,12}$", id_number):
        return False, "Numer dokumentu musi mieć 6-12 znaków alfanumerycznych."
    return True, None


def validate_password(password):
    """Waliduje hasło - min 8 znaków, litera i cyfra."""
    if not password or len(password) < 8:
        return False, "Hasło musi mieć minimum 8 znaków."
    if not re.search(r"[a-zA-Z]", password) or not re.search(r"\d", password):
        return False, "Hasło musi zawierać co najmniej jedną literę i cyfrę."
    return True, None


def validate_positive_number(value, field_name="Wartość", min_val=1, max_val=None):
    """Waliduje liczbę dodatnią."""
    try:
        num = float(value)
        if num < min_val:
            return False, f"{field_name} musi być >= {min_val}."
        if max_val and num > max_val:
            return False, f"{field_name} musi być <= {max_val}."
        return True, None
    except (ValueError, TypeError):
        return False, f"{field_name} musi być liczbą."


def requires_role(role_name):
    """Dekorator do sprawdzania, czy zalogowany użytkownik ma wymaganą rolę."""

    def decorator(f):
        @wraps(f)
        @login_required
        def decorated_function(*args, **kwargs):
            if role_name not in current_user.role.lower():
                flash("Nie masz wystarczających uprawnień do tej akcji.", "danger")
                return redirect(url_for("dashboard"))
            return f(*args, **kwargs)

        return decorated_function

    return decorator


@app.route("/employees")
@requires_role("manager")
def list_employees():
    """Wyświetla listę wszystkich pracowników (employees.html)."""
    employees = []
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
        query = """
            SELECT
                employee_id AS id,
                first_name,
                last_name,
                position,
                email
            FROM employees
            ORDER BY last_name, first_name
        """
        cur.execute(query)
        log_sql(cur, query)
        employees = cur.fetchall()
        cur.close()
        conn.close()
    except psycopg2.Error as e:
        flash(f"Błąd bazy danych: {e}", "danger")

    is_manager = "manager" in current_user.role.lower()
    return render_template("employees.html", employees=employees, is_manager=is_manager)


@app.route("/employees/add", methods=["GET", "POST"])
@requires_role("manager")
def add_employee():
    """Dodawanie nowego pracownika (employees_form.html)."""
    if request.method == "POST":
        first_name = request.form["first_name"]
        last_name = request.form["last_name"]
        email = request.form["email"]
        password = request.form["password"]
        position = request.form["position"]
        phone = request.form.get("phone")
        hire_date = request.form["hire_date"]

        if not all([first_name, last_name, email, password, position, hire_date]):
            flash("Wypełnij wszystkie wymagane pola!", "danger")
            return render_template("employees_form.html", form_data=request.form)

        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute(
                """
                CALL create_db_user_and_employee(
                    p_password := %s,
                    p_first_name := %s,
                    p_last_name := %s,
                    p_position := %s,
                    p_hire_date := %s,
                    p_email := %s,
                    p_phone := %s
                )
            """,
                (password, first_name, last_name, position, hire_date, email, phone),
            )

            log_sql(
                cur,
                """
                CALL create_db_user_and_employee(
                    p_password := %s,
                    p_first_name := %s,
                    p_last_name := %s,
                    p_position := %s,
                    p_hire_date := %s,
                    p_email := %s,
                    p_phone := %s
                )
            """,
                (password, first_name, last_name, position, hire_date, email, phone),
            )
            conn.commit()
            cur.close()
            conn.close()

            flash(
                f"Pomyślnie dodano nowego pracownika: {first_name} {last_name} ({position}).",
                "success",
            )
            return redirect(url_for("list_employees"))

        except psycopg2.errors.UniqueViolation:
            flash(
                f"Błąd: Pracownik o podanym adresie e-mail ({email}) już istnieje w systemie (unikalny login DB).",
                "danger",
            )
            return render_template("employees_form.html", form_data=request.form)
        except psycopg2.Error as e:
            flash(f"Błąd bazy danych podczas dodawania pracownika: {e}", "danger")
            return render_template("employees_form.html", form_data=request.form)
        except Exception as e:
            flash(f"Nieoczekiwany błąd: {e}", "danger")
            return render_template("employees_form.html", form_data=request.form)

    return render_template("employees_form.html")


@app.route("/employees/edit/<int:employee_id>", methods=["GET", "POST"])
@requires_role("manager")
def edit_employee(employee_id):
    """Edycja danych pracownika (edit_employee.html)."""
    conn = None
    cur = None
    employee = None

    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

        if request.method == "POST":
            first_name = request.form["first_name"]
            last_name = request.form["last_name"]
            position = request.form["position"]
            email = request.form["email"]

            cur.execute(
                """
                UPDATE employees
                SET first_name = %s, last_name = %s, position = %s, email = %s
                WHERE employee_id = %s
            """,
                (first_name, last_name, position, email, employee_id),
            )

            log_sql(
                cur,
                """
                UPDATE employees
                SET first_name = %s, last_name = %s, position = %s, email = %s
                WHERE employee_id = %s
            """,
                (first_name, last_name, position, email, employee_id),
            )
            conn.commit()

            flash("Pomyślnie zaktualizowano dane pracownika.", "success")
            return redirect(url_for("list_employees"))

        cur.execute(
            """
            SELECT
                employee_id AS id,
                first_name,
                last_name,
                position,
                email
            FROM employees
            WHERE employee_id = %s
        """,
            (employee_id,),
        )

        log_sql(
            cur,
            """
            SELECT
                employee_id AS id,
                first_name,
                last_name,
                position,
                email
            FROM employees
            WHERE employee_id = %s
        """,
            (employee_id,),
        )
        employee = cur.fetchone()

        if not employee:
            flash(
                f"Błąd: Pracownik o ID {employee_id} nie został znaleziony.", "danger"
            )
            return redirect(url_for("list_employees"))

    except psycopg2.Error as e:
        flash(f"Błąd bazy danych: {e}", "danger")

        class MockEmployee:
            def __init__(self, data):
                self.id = employee_id
                self.first_name = data["first_name"]
                self.last_name = data["last_name"]
                self.position = data["position"]
                self.email = data["email"]

        return render_template(
            "edit_employee.html", employee=MockEmployee(request.form)
        )
    except Exception as e:
        flash(f"Nieoczekiwany błąd: {e}", "danger")

        class MockEmployee:
            def __init__(self, data):
                self.id = employee_id
                self.first_name = data["first_name"]
                self.last_name = data["last_name"]
                self.position = data["position"]
                self.email = data["email"]

        return render_template(
            "edit_employee.html", employee=MockEmployee(request.form)
        )
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

    return render_template("edit_employee.html", employee=employee)


@app.route("/employees/delete/<int:employee_id>", methods=["POST"])
@requires_role("manager")
def delete_employee(employee_id):
    """Usuwanie pracownika i jego konta DB (roli)."""
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

        cur.execute(
            "SELECT email FROM employees WHERE employee_id = %s", (employee_id,)
        )
        result = cur.fetchone()

        log_sql(
            cur, "SELECT email FROM employees WHERE employee_id = %s", (employee_id,)
        )
        if not result:
            flash(f"Pracownik o ID {employee_id} nie został znaleziony.", "danger")
            return redirect(url_for("list_employees"))

        employee_email = result["email"]

        cur.execute("DELETE FROM employees WHERE employee_id = %s", (employee_id,))

        log_sql(cur, query)
        try:
            # Używamy procedury SECURITY DEFINER, aby ominąć brak uprawnień CREATEROLE
            cur.execute("CALL delete_db_role(%s)", (employee_email,))
            log_sql(cur, query)
        except psycopg2.Error as e:
            flash(
                f"Ostrzeżenie: Usunięto pracownika, ale nie udało się usunąć roli DB. Wymagana ręczna interwencja DBA. Błąd: {e}",
                "warning",
            )

        conn.commit()
        flash(
            f"Pomyślnie usunięto pracownika (ID: {employee_id}) i powiązane konto DB.",
            "success",
        )

    except psycopg2.Error as e:
        flash(f"Błąd bazy danych podczas usuwania pracownika: {e}", "danger")
    except Exception as e:
        flash(f"Nieoczekiwany błąd: {e}", "danger")
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

    return redirect(url_for("list_employees"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]

        try:
            conn = psycopg2.connect(
                host="localhost",
                database=Config.DATABASE["database"],
                user=username,
                password=password,
                port=5432,
                connect_timeout=3,
            )

            cur = conn.cursor()

            cur.execute(
                """
                SELECT position FROM employees
                WHERE email = %s
            """,
                (username,),
            )

            log_sql(
                cur,
                """
                SELECT position FROM employees
                WHERE email = %s
            """,
                (username,),
            )
            role_result = cur.fetchone()
            cur.close()
            conn.close()

            if role_result is None:
                flash(
                    "Błąd logowania: Nie znaleziono pracownika powiązanego z tym loginem.",
                    "danger",
                )
                return redirect(url_for("login"))

            employee_position = role_result[0]

            session["db_user"] = username
            session["db_password"] = password
            session["role"] = employee_position
            user = User(username, employee_position)
            login_user(user)

            flash(
                f"Zalogowano pomyślnie jako {username} ({employee_position}).",
                "success",
            )
            return redirect(url_for("dashboard"))

        except psycopg2.OperationalError as e:
            flash("Błąd logowania: Nieprawidłowy login lub hasło.", "danger")
            print(f"Błąd logowania: {e}")
        except Exception as e:
            flash(f"Wystąpił nieoczekiwany błąd: {e}", "danger")
            print(f"Nieoczekiwany błąd: {e}")

    return render_template("login.html")


@app.route("/logout")
@login_required
def logout():
    session.pop("db_user", None)
    session.pop("db_password", None)
    session.pop("role", None)
    logout_user()
    flash("Wylogowano pomyślnie.", "success")
    return redirect(url_for("login"))


@app.route("/")
@login_required
def dashboard():
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    query_reservations = """
    SELECT * FROM view_current_reservations
    """
    cur.execute(query_reservations)
    log_sql(cur, query_reservations)
    reservations = cur.fetchall()

    cleaning_rooms = []
    if "cleaning" in current_user.role or "manager" in current_user.role:
        query_cleaning = """
            SELECT room_id, room_number, room_type FROM rooms
            WHERE status = 'cleaning'
        """
        cur.execute(query_cleaning)
        log_sql(cur, query_cleaning)
        cleaning_rooms = (
            cur.fetchall()
        )

    cur.close()
    conn.close()

    return render_template(
        "dashboard.html", reservations=reservations, cleaning_rooms=cleaning_rooms
    )


@app.route("/checkin/<int:res_id>")
@login_required
def checkin(res_id):
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do zameldowania gościa.", "danger")
        return redirect(url_for("dashboard"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            UPDATE reservations
            SET reservation_status = 'checked_in',
                check_in_employee_id = (SELECT employee_id FROM employees WHERE position = %s LIMIT 1)
            WHERE reservation_id = %s AND reservation_status = 'confirmed'
        """,
            (current_user.role, res_id),
        )

        log_sql(
            cur,
            """
            UPDATE reservations
            SET reservation_status = 'checked_in',
                check_in_employee_id = (SELECT employee_id FROM employees WHERE position = %s LIMIT 1)
            WHERE reservation_id = %s AND reservation_status = 'confirmed'
        """,
            (current_user.role, res_id),
        )
        if cur.rowcount == 0:
            flash(
                f"Błąd: Nie można zameldować rezerwacji #{res_id}. Sprawdź status.",
                "danger",
            )
            conn.rollback()
        else:
            conn.commit()
            flash(
                f"Gość zameldowany pomyślnie (rezerwacja #{res_id}). Status pokoju zmieniony na ZAJĘTY.",
                "success",
            )

    except psycopg2.errors.RaiseException as e:
        flash(f"Błąd Check-in: {e}", "danger")
        conn.rollback()
    except Exception as e:
        flash(f"Wystąpił błąd DB: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

    return redirect(url_for("dashboard"))


@app.route("/checkout/<int:res_id>")
@login_required
def checkout(res_id):
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do wymeldowania gościa.", "danger")
        return redirect(url_for("dashboard"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("CALL checkout(%s)", (res_id,))

        log_sql(cur, "CALL checkout(%s)", (res_id,))
        conn.commit()
        flash(
            f"Gość wymeldowany pomyślnie (rezerwacja #{res_id}). Pokój oznaczony jako DO SPRZĄTANIA.",
            "success",
        )
    except psycopg2.errors.RaiseException as e:
        flash(f"Błąd wymeldowania: {e}", "danger")
        conn.rollback()
    except Exception as e:
        flash(f"Wystąpił błąd DB: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("dashboard"))


@app.route("/cancel_reservation/<int:res_id>")
@login_required
def cancel_reservation(res_id):
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do anulowania rezerwacji.", "danger")
        return redirect(url_for("reservations_list"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("CALL cancel_reservation(%s)", (res_id,))

        log_sql(cur, "CALL cancel_reservation(%s)", (res_id,))
        conn.commit()
        flash(f"Rezerwacja #{res_id} została anulowana, pokój zwolniony.", "success")
    except psycopg2.errors.RaiseException as e:
        flash(f"Błąd anulowania: {e}", "danger")
        conn.rollback()
    except Exception as e:
        flash(f"Wystąpił błąd DB: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("reservations_list"))


@app.route("/room_cleaned/<int:room_id>")
@login_required
def room_cleaned(room_id):
    if current_user.role not in ["cleaning", "manager"]:
        flash("Brak uprawnień do zmiany statusu pokoju.", "danger")
        return redirect(url_for("dashboard"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("CALL room_cleaned(%s)", (room_id,))
        log_sql(cur, "CALL room_cleaned(%s)", (room_id,))
        conn.commit()
        flash(f"Pokój o ID {room_id} oznaczony jako WOLNY.", "success")
    except psycopg2.errors.RaiseException as e:
        flash(f"Błąd: {e}", "danger")
        conn.rollback()
    except Exception as e:
        flash(f"Wystąpił błąd DB: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("dashboard"))




@app.route("/guests")
@login_required
def guests_list():
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    try:
        query = """
            SELECT guest_id, first_name, last_name, email, phone,
                   nationality, gender
            FROM guests
            ORDER BY last_name
        """
        cur.execute(query)
        log_sql(cur, query)
        guests = cur.fetchall()
    except psycopg2.errors.UndefinedColumn:
        conn.rollback()
        query = """
            SELECT guest_id, first_name, last_name, email, phone,
                   NULL as nationality, NULL as gender
            FROM guests
            ORDER BY last_name
        """
        cur.execute(query)
        log_sql(cur, query)
        guests = cur.fetchall()
        flash(
            "Uwaga: Kolumny nationality i gender nie istnieją w bazie. Uruchom migrate_guests.sql jako administrator bazy.",
            "warning",
        )

    cur.close()
    conn.close()

    return render_template("guests_list.html", guests=guests)


@app.route("/guests/add", methods=["GET", "POST"])
@login_required
def guests_add():
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do dodawania gości.", "danger")
        return redirect(url_for("guests_list"))

    if request.method == "POST":
        data = request.form

        errors = []
        valid, msg = validate_name(data.get("first_name"), "Imię")
        if not valid:
            errors.append(msg)
        valid, msg = validate_name(data.get("last_name"), "Nazwisko")
        if not valid:
            errors.append(msg)
        valid, msg = validate_email(data.get("email"))
        if not valid:
            errors.append(msg)
        valid, msg = validate_phone(data.get("phone"))
        if not valid:
            errors.append(msg)
        valid, msg = validate_id_number(data.get("id_number"))
        if not valid:
            errors.append(msg)

        if errors:
            for error in errors:
                flash(error, "danger")
            mock_guest = (
                None,
                data.get("first_name", ""),
                data.get("last_name", ""),
                data.get("email", ""),
                data.get("phone", ""),
                data.get("address", ""),
                data.get("id_number", ""),
            )
            return render_template("guests_form.html", guest=mock_guest)

        conn = get_db_connection()
        cur = conn.cursor()
        try:
            query = """
                INSERT INTO guests (first_name, last_name, email, phone, address, id_number, date_of_birth, nationality, gender)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """
            date_of_birth = data.get("date_of_birth") or None
            nationality = data.get("nationality", "").strip() or None
            gender = data.get("gender") or None
            params = (
                data["first_name"].strip(),
                data["last_name"].strip(),
                data["email"].strip().lower(),
                data.get("phone", "").strip(),
                data.get("address", "").strip(),
                data["id_number"].strip().upper(),
                date_of_birth,
                nationality,
                gender,
            )
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash("Gość dodany pomyślnie.", "success")
            return redirect(url_for("guests_list"))
        except psycopg2.errors.UniqueViolation:
            flash(
                "Błąd: Gość z tym numerem ID/Paszportu lub emailem już istnieje.",
                "danger",
            )
            conn.rollback()
            mock_guest = (
                None,
                data["first_name"],
                data["last_name"],
                data["email"],
                data["phone"],
                data["address"],
                data["id_number"],
            )
            return render_template("guests_form.html", guest=mock_guest)
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
        finally:
            cur.close()
            conn.close()

    return render_template("guests_form.html", guest=None)


@app.route("/guests/edit/<int:guest_id>", methods=["GET", "POST"])
@login_required
def guests_edit(guest_id):
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do edycji gości.", "danger")
        return redirect(url_for("guests_list"))

    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )

    if request.method == "POST":
        data = request.form
        try:
            query = """
                UPDATE guests SET first_name = %s, last_name = %s, email = %s,
                phone = %s, address = %s, id_number = %s, date_of_birth = %s, nationality = %s, gender = %s
                WHERE guest_id = %s
            """
            date_of_birth = data.get("date_of_birth") or None
            nationality = data.get("nationality", "").strip() or None
            gender = data.get("gender") or None
            params = (
                data["first_name"],
                data["last_name"],
                data["email"],
                data["phone"],
                data["address"],
                data["id_number"],
                date_of_birth,
                nationality,
                gender,
                guest_id,
            )
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash("Dane gościa zaktualizowane pomyślnie.", "success")
            return redirect(url_for("guests_list"))
        except psycopg2.errors.UniqueViolation:
            flash("Błąd: Gość z tym numerem ID/Paszportu już istnieje.", "danger")
            conn.rollback()
            mock_guest = (
                guest_id,
                data["first_name"],
                data["last_name"],
                data["email"],
                data["phone"],
                data["address"],
                data["id_number"],
            )
            return render_template("guests_form.html", guest=mock_guest)
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
            mock_guest = (
                guest_id,
                data["first_name"],
                data["last_name"],
                data["email"],
                data["phone"],
                data["address"],
                data["id_number"],
            )
            return render_template("guests_form.html", guest=mock_guest)
        finally:
            cur.close()
            conn.close()

    cur.execute(
        """
        SELECT guest_id, first_name, last_name, email, phone, address, id_number, date_of_birth, nationality, gender
        FROM guests WHERE guest_id = %s
    """,
        (guest_id,),
    )

    log_sql(
        cur,
        """
        SELECT guest_id, first_name, last_name, email, phone, address, id_number, date_of_birth, nationality, gender
        FROM guests WHERE guest_id = %s
    """,
        (guest_id,),
    )
    guest = cur.fetchone()
    cur.close()
    conn.close()

    if guest is None:
        flash("Gość nie znaleziony.", "danger")
        return redirect(url_for("guests_list"))

    return render_template("guests_form.html", guest=guest)


@app.route("/guest/<int:guest_id>/history")
@login_required
def guest_history(guest_id):
    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )

    query_guest = """
        SELECT first_name, last_name, email, phone
        FROM guests WHERE guest_id = %s
    """
    cur.execute(query_guest, (guest_id,))
    log_sql(cur, query_guest, (guest_id,))
    guest = cur.fetchone()

    query_reservations = """
        SELECT r.reservation_id, ro.room_number, r.check_in_date, r.check_out_date,
               r.total_cost, r.reservation_status
        FROM reservations r
        JOIN rooms ro ON r.room_id = ro.room_id
        WHERE r.guest_id = %s
        ORDER BY r.check_in_date DESC
    """
    cur.execute(query_reservations, (guest_id,))
    log_sql(cur, query_reservations, (guest_id,))
    reservations = cur.fetchall()

    cur.close()
    conn.close()

    if guest is None:
        flash("Gość nie znaleziony.", "danger")
        return redirect(url_for("guests_list"))

    return render_template("guest_history.html", guest=guest, reservations=reservations)




@app.route("/rooms")
@login_required
def rooms_list():
    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )
    query = """
        SELECT room_id, room_number, room_type, price_per_night, status, capacity
        FROM rooms
        ORDER BY room_number
    """
    cur.execute(query)
    log_sql(cur, query)
    rooms = cur.fetchall()
    cur.close()
    conn.close()
    return render_template("rooms_list.html", rooms=rooms)


@app.route("/rooms/add", methods=["GET", "POST"])
@login_required
def rooms_add():
    if current_user.role not in ["manager"]:
        flash("Brak uprawnień do dodawania pokoi.", "danger")
        return redirect(url_for("rooms_list"))

    if request.method == "POST":
        data = request.form
        conn = get_db_connection()
        cur = conn.cursor()
        try:
            query = """
                INSERT INTO rooms (room_number, room_type, price_per_night, status, capacity)
                VALUES (%s, %s, %s, 'free', %s)
            """
            params = (
                data["room_number"],
                data["room_type"],
                data["price_per_night"],
                data["capacity"],
            )
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash(f"Pokój {data['room_number']} dodany pomyślnie.", "success")
            return redirect(url_for("rooms_list"))
        except psycopg2.errors.UniqueViolation:
            flash("Błąd: Pokój o tym numerze już istnieje.", "danger")
            conn.rollback()
            return render_template("rooms_form.html", room=None, form_data=request.form)
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
            return render_template("rooms_form.html", room=None, form_data=request.form)
        finally:
            cur.close()
            conn.close()

    return render_template("rooms_form.html", room=None)


@app.route("/rooms/edit/<int:room_id>", methods=["GET", "POST"])
@login_required
def rooms_edit(room_id):
    if current_user.role not in ["manager"]:
        flash("Brak uprawnień do edycji pokoi.", "danger")
        return redirect(url_for("rooms_list"))

    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )  

    if request.method == "POST":
        data = request.form
        try:
            query = """
                UPDATE rooms SET room_number = %s, room_type = %s,
                price_per_night = %s, capacity = %s
                WHERE room_id = %s
            """
            params = (
                data["room_number"],
                data["room_type"],
                data["price_per_night"],
                data["capacity"],
                room_id,
            )
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash(f"Pokój {data['room_number']} zaktualizowany pomyślnie.", "success")
            return redirect(url_for("rooms_list"))
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
            mock_room = (
                room_id,
                data["room_number"],
                data["room_type"],
                data["price_per_night"],
                "free",  
                data["capacity"],
            )
            return render_template("rooms_form.html", room=mock_room)
        finally:
            cur.close()
            conn.close()

    cur.execute(
        """
        SELECT room_id, room_number, room_type, price_per_night, status, capacity
        FROM rooms WHERE room_id = %s
    """,
        (room_id,),
    )

    log_sql(
        cur,
        """
        SELECT room_id, room_number, room_type, price_per_night, status, capacity
        FROM rooms WHERE room_id = %s
    """,
        (room_id,),
    )
    room = cur.fetchone()
    cur.close()
    conn.close()

    if room is None:
        flash("Pokój nie znaleziony.", "danger")
        return redirect(url_for("rooms_list"))

    return render_template("rooms_form.html", room=room)


@app.route("/rooms/set_status/<int:room_id>/<status>")
@requires_role("manager")
def set_room_status(room_id, status):
    """Zmiana statusu pokoju."""
    valid_statuses = ["free", "occupied", "cleaning", "maintenance"]

    if status not in valid_statuses:
        flash(
            f"Nieprawidłowy status: {status}. Dozwolone: {', '.join(valid_statuses)}",
            "danger",
        )
        return redirect(url_for("rooms_list"))

    status_names = {
        "free": "Wolny",
        "occupied": "Zajęty",
        "cleaning": "Do sprzątania",
        "maintenance": "W remoncie",
    }

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        query = "UPDATE rooms SET status = %s WHERE room_id = %s"
        params = (status, room_id)
        cur.execute(query, params)
        log_sql(cur, query, params)
        conn.commit()
        flash(
            f"Status pokoju zmieniony na: {status_names.get(status, status)}", "success"
        )
    except psycopg2.Error as e:
        flash(f"Błąd bazy danych: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

    return redirect(url_for("rooms_list"))




@app.route("/reservations")
@login_required
def reservations_list():
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    query = """
    SELECT * FROM view_all_reservations
    """
    cur.execute(query)
    log_sql(cur, query)
    reservations = cur.fetchall()

    cur.close()
    conn.close()
    return render_template("reservations_list.html", reservations=reservations)




@app.route("/reservation/new", methods=["GET", "POST"])
@login_required
def new_reservation():
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do tworzenia rezerwacji.", "danger")
        return redirect(url_for("dashboard"))

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    guests = []
    rooms = []

    if request.method == "POST":
        data = request.form
        guest_id = data["guest_id"]
        room_id = data["room_id"]
        check_in = data["check_in"]
        check_out = data["check_out"]
        number_of_guests = data.get("number_of_guests", 1)

        employee_id = None
        try:
            cur.execute(
                """
                SELECT employee_id FROM employees WHERE position = %s LIMIT 1
            """,
                (current_user.role,),
            )

            log_sql(
                cur,
                """
                SELECT employee_id FROM employees WHERE position = %s LIMIT 1
            """,
                (current_user.role,),
            )
            employee_data = cur.fetchone()

            if employee_data:
                employee_id = employee_data["employee_id"]
            else:
                flash(
                    f"Błąd: Nie można znaleźć ID pracownika dla roli {current_user.role}.",
                    "danger",
                )
                cur.close()
                conn.close()
                return render_template(
                    "reservation_form.html",
                    guests=guests,
                    rooms=rooms,
                    form_data=request.form,
                )

        except Exception as e:
            flash(f"Błąd pobierania ID pracownika: {e}", "danger")
            cur.close()
            conn.close()
            return render_template(
                "reservation_form.html",
                guests=guests,
                rooms=rooms,
                form_data=request.form,
            )

        try:
            cur.execute(
                """
                CALL create_reservation(
                    p_check_in_date := %s,
                    p_check_out_date := %s,
                    p_guest_id := %s,
                    p_room_id := %s,
                    p_employee_id := %s, -- Przekazujemy ID, a nie podzapytanie
                    p_number_of_guests := %s
                )
            """,
                (check_in, check_out, guest_id, room_id, employee_id, number_of_guests),
            )

            log_sql(
                cur,
                """
                CALL create_reservation(
                    p_check_in_date := %s,
                    p_check_out_date := %s,
                    p_guest_id := %s,
                    p_room_id := %s,
                    p_employee_id := %s, -- Przekazujemy ID, a nie podzapytanie
                    p_number_of_guests := %s
                )
            """,
                (check_in, check_out, guest_id, room_id, employee_id, number_of_guests),
            )
            conn.commit()
            flash("Nowa rezerwacja utworzona pomyślnie.", "success")

            cur.close()
            conn.close()
            return redirect(url_for("reservations_list"))

        except psycopg2.errors.RaiseException as e:
            flash(f"Błąd tworzenia rezerwacji: {e}", "danger")
            conn.rollback()
            return render_template(
                "reservation_form.html",
                guests=guests,
                rooms=rooms,
                form_data=request.form,
            )
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
            return render_template(
                "reservation_form.html",
                guests=guests,
                rooms=rooms,
                form_data=request.form,
            )

    try:
        cur.execute(
            "SELECT guest_id, first_name || ' ' || last_name AS guest_full_name FROM guests ORDER BY last_name"
        )

        log_sql(
            cur,
            "SELECT guest_id, first_name || ' ' || last_name AS guest_full_name FROM guests ORDER BY last_name",
        )
        guests = cur.fetchall()

        cur.execute(
            "SELECT room_id, room_number || ' (' || room_type || ', ' || price_per_night || ' PLN)' AS room_display FROM rooms WHERE status != 'maintenance' ORDER BY room_number"
        )

        log_sql(
            cur,
            "SELECT room_id, room_number || ' (' || room_type || ', ' || price_per_night || ' PLN)' AS room_display FROM rooms WHERE status != 'maintenance' ORDER BY room_number",
        )
        rooms = cur.fetchall()

    except Exception as e:
        flash(f"Błąd pobierania danych do formularza: {e}", "danger")

    finally:
        cur.close()
        conn.close()

    return render_template("reservation_form.html", guests=guests, rooms=rooms)




@app.route("/api/guest/<int:guest_id>/discount")
@login_required
def get_guest_discount(guest_id):
    """Zwraca rabat lojalnościowy dla gościa (JSON API)."""


    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT get_guest_loyalty_discount(%s)", (guest_id,))

        log_sql(cur, query)
        discount = cur.fetchone()[0]
        discount_percent = int(float(discount) * 100)

        cur.execute(
            """
            SELECT COUNT(*) FROM reservations
            WHERE guest_id = %s AND reservation_status = 'checked_out'
        """,
            (guest_id,),
        )

        log_sql(
            cur,
            """
            SELECT COUNT(*) FROM reservations
            WHERE guest_id = %s AND reservation_status = 'checked_out'
        """,
            (guest_id,),
        )
        stays = cur.fetchone()[0]

        return jsonify({
            "guest_id": guest_id,
            "discount": float(discount),
            "discount_percent": discount_percent,
            "past_stays": stays,
            "message": (
                f"{discount_percent}% rabatu za {stays} pobytów"
                if discount_percent > 0
                else "Brak rabatu"
            ),
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


@app.route("/services")
@login_required
def services_list():
    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )  
    query = """
        SELECT service_id, service_name, price, description
        FROM services
        ORDER BY service_name
    """
    cur.execute(query)
    log_sql(cur, query)
    services = cur.fetchall()
    cur.close()
    conn.close()
    return render_template("services_list.html", services=services)



@app.route("/services/type/add", methods=["GET", "POST"])
@requires_role("manager")
def add_service_type():
    """Pozwala menadżerowi na dodanie nowego typu usługi."""

    if request.method == "POST":
        name = request.form.get("name")
        description = request.form.get("description", "")
        price_str = request.form.get("price")

        # Walidacja
        if not all([name, price_str]):
            flash("Nazwa i cena są wymaganymi polami.", "warning")
            return render_template("add_service_type.html", title="Dodaj Typ Usługi")

        try:
            price = float(price_str)
        except ValueError:
            flash("Cena musi być liczbą.", "danger")
            return render_template("add_service_type.html", title="Dodaj Typ Usługi")

        conn = get_db_connection()
        cur = conn.cursor()
        try:
            query = """
                INSERT INTO services (service_name, price, description)
                VALUES (%s, %s, %s)
            """
            params = (name, price, description)
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash(f'Usługa "{name}" została dodana pomyślnie.', "success")
            return redirect(url_for("services_list"))
        except psycopg2.errors.UniqueViolation:
            flash("Błąd: Usługa o tej nazwie już istnieje.", "danger")
            conn.rollback()
        except Exception as e:
            flash(f"Błąd bazy danych: {e}", "danger")
            conn.rollback()
        finally:
            cur.close()
            conn.close()

    return render_template("add_service_type.html", title="Dodaj Typ Usługi")


@app.route("/services/edit/<int:service_id>", methods=["GET", "POST"])
@requires_role("manager")
def edit_service(service_id):
    """Edycja istniejącej usługi."""
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    if request.method == "POST":
        name = request.form.get("name")
        description = request.form.get("description", "")
        price_str = request.form.get("price")

        if not all([name, price_str]):
            flash("Nazwa i cena są wymaganymi polami.", "warning")
            cur.execute("SELECT * FROM services WHERE service_id = %s", (service_id,))

            log_sql(cur, "SELECT * FROM services WHERE service_id = %s", (service_id,))
            service = cur.fetchone()
            cur.close()
            conn.close()
            return render_template(
                "add_service_type.html", title="Edytuj Usługę", service=service
            )

        try:
            price = float(price_str)
        except ValueError:
            flash("Cena musi być liczbą.", "danger")
            cur.execute("SELECT * FROM services WHERE service_id = %s", (service_id,))

            log_sql(cur, "SELECT * FROM services WHERE service_id = %s", (service_id,))
            service = cur.fetchone()
            cur.close()
            conn.close()
            return render_template(
                "add_service_type.html", title="Edytuj Usługę", service=service
            )

        try:
            query = """
                UPDATE services
                SET service_name = %s, price = %s, description = %s
                WHERE service_id = %s
            """
            params = (name, price, description, service_id)
            cur.execute(query, params)
            log_sql(cur, query, params)
            conn.commit()
            flash(f'Usługa "{name}" została zaktualizowana.', "success")
            return redirect(url_for("services_list"))
        except psycopg2.Error as e:
            flash(f"Błąd bazy danych: {e}", "danger")
            conn.rollback()
        finally:
            cur.close()
            conn.close()

    query = "SELECT * FROM services WHERE service_id = %s"
    cur.execute(query, (service_id,))
    log_sql(cur, query, (service_id,))
    service = cur.fetchone()
    cur.close()
    conn.close()

    if not service:
        flash("Usługa nie została znaleziona.", "danger")
        return redirect(url_for("services_list"))

    return render_template(
        "add_service_type.html", title="Edytuj Usługę", service=service
    )


@app.route("/services/delete/<int:service_id>", methods=["POST"])
@requires_role("manager")
def delete_service(service_id):
    """Usuwanie usługi."""
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "SELECT COUNT(*) FROM service_orders WHERE service_id = %s", (service_id,)
        )

        log_sql(
            cur,
            "SELECT COUNT(*) FROM service_orders WHERE service_id = %s",
            (service_id,),
        )
        count = cur.fetchone()[0]

        if count > 0:
            flash(
                f"Nie można usunąć usługi - jest powiązana z {count} zamówieniami.",
                "danger",
            )
        else:
            query = "DELETE FROM services WHERE service_id = %s"
            cur.execute(query, (service_id,))
            log_sql(cur, query, (service_id,))
            conn.commit()
            flash("Usługa została usunięta.", "success")
    except psycopg2.Error as e:
        flash(f"Błąd bazy danych: {e}", "danger")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

    return redirect(url_for("services_list"))




@app.route("/add_service/<int:res_id>", methods=["GET", "POST"])
@login_required
def add_service(res_id):
    if current_user.role not in ["receptionist", "manager"]:
        flash("Brak uprawnień do dodawania usług.", "danger")
        return redirect(url_for("reservations_list"))

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    services = []

    if request.method == "POST":
        data = request.form
        service_id = data["service_id"]
        quantity = data["quantity"]

        employee_id = None
        try:
            cur.execute(
                """
                SELECT employee_id FROM employees WHERE position = %s LIMIT 1
            """,
                (current_user.role,),
            )

            log_sql(
                cur,
                """
                SELECT employee_id FROM employees WHERE position = %s LIMIT 1
            """,
                (current_user.role,),
            )
            employee_data = cur.fetchone()

            if employee_data:
                employee_id = employee_data["employee_id"]
            else:
                flash(
                    f"Błąd: Nie można znaleźć ID pracownika dla roli {current_user.role}.",
                    "danger",
                )
                cur.close()
                conn.close()
                return render_template(
                    "add_service.html",
                    res_id=res_id,
                    services=services,
                    form_data=request.form,
                )

        except Exception as e:
            flash(f"Błąd pobierania ID pracownika: {e}", "danger")
            cur.close()
            conn.close()
            return render_template(
                "add_service.html",
                res_id=res_id,
                services=services,
                form_data=request.form,
            )

        try:
            query = """
                CALL add_service_to_reservation(
                    p_reservation_id := %s,
                    p_service_id := %s,
                    p_quantity := %s,
                    p_service_employee_id := %s -- Przekazujemy ID, a nie podzapytanie
                )
            """
            params = (res_id, service_id, quantity, employee_id)
            cur.execute(query, params)
            log_sql(cur, query, params)

            conn.commit()
            flash(f"Usługa dodana do rezerwacji #{res_id}.", "success")

            cur.close()
            conn.close()
            return redirect(url_for("reservations_list"))

        except psycopg2.errors.RaiseException as e:
            flash(f"Błąd dodawania usługi: {e}", "danger")
            conn.rollback()
            return render_template(
                "add_service.html",
                res_id=res_id,
                services=services,
                form_data=request.form,
            )
        except Exception as e:
            flash(f"Wystąpił błąd DB: {e}", "danger")
            conn.rollback()
            return render_template(
                "add_service.html",
                res_id=res_id,
                services=services,
                form_data=request.form,
            )

    reservation_check = None

    try:
        query_services = (
            "SELECT service_id, service_name, price FROM services ORDER BY service_name"
        )
        cur.execute(query_services)
        log_sql(cur, query_services)
        services = cur.fetchall()

        query_res = "SELECT reservation_id FROM reservations WHERE reservation_id = %s"
        cur.execute(query_res, (res_id,))
        log_sql(cur, query_res, (res_id,))
        reservation_check = cur.fetchone()

    except Exception as e:
        flash(f"Błąd pobierania danych do formularza: {e}", "danger")

    finally:
        cur.close()
        conn.close()

    if not reservation_check:
        flash(f"Rezerwacja #{res_id} nie została znaleziona.", "danger")
        return redirect(url_for("reservations_list"))

    return render_template("add_service.html", res_id=res_id, services=services)


@app.route("/reports")
@login_required
def reports():
    role_lower = current_user.role.lower()

    is_authorized = "manager" in role_lower or "accountant" in role_lower

    if not is_authorized:
        flash(
            "Brak uprawnień do przeglądania raportów. Wymagana rola: Manager lub Accounting.",
            "danger",
        )
        return redirect(url_for("dashboard"))

    conn = get_db_connection()

    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    query1 = "SELECT * FROM view_revenue_report LIMIT 12"
    cur.execute(query1)
    log_sql(cur, query1)
    revenue = cur.fetchall()

    query2 = "SELECT * FROM view_guest_history ORDER BY total_spent DESC LIMIT 10"
    cur.execute(query2)
    log_sql(cur, query2)
    top_guests = cur.fetchall()

    query3 = "SELECT occupied_rooms, total_rooms, occupancy_percentage FROM view_hotel_occupancy"
    cur.execute(query3)
    log_sql(cur, query3)
    occupancy = cur.fetchone() or {
        "occupied_rooms": 0,
        "total_rooms": 0,
        "occupancy_percentage": 0.0,
    }

    cur.close()
    conn.close()

    return render_template(
        "reports.html", revenue=revenue, top_guests=top_guests, occupancy=occupancy
    )



@app.route("/reservation/<int:res_id>/pay", methods=["GET", "POST"])
@login_required
def pay_reservation(res_id):
    """Rejestracja płatności dla rezerwacji."""
    if current_user.role not in ["receptionist", "manager", "accountant"]:
        flash("Brak uprawnień do rejestrowania płatności.", "danger")
        return redirect(url_for("reservations_list"))

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    cur.execute(
        """
        SELECT r.reservation_id, r.total_cost, r.reservation_status,
               g.first_name || ' ' || g.last_name AS guest_name,
               ro.room_number
        FROM reservations r
        JOIN guests g ON r.guest_id = g.guest_id
        JOIN rooms ro ON r.room_id = ro.room_id
        WHERE r.reservation_id = %s
    """,
        (res_id,),
    )

    log_sql(
        cur,
        """
        SELECT r.reservation_id, r.total_cost, r.reservation_status,
               g.first_name || ' ' || g.last_name AS guest_name,
               ro.room_number
        FROM reservations r
        JOIN guests g ON r.guest_id = g.guest_id
        JOIN rooms ro ON r.room_id = ro.room_id
        WHERE r.reservation_id = %s
    """,
        (res_id,),
    )
    reservation = cur.fetchone()

    if not reservation:
        flash(f"Rezerwacja #{res_id} nie została znaleziona.", "danger")
        cur.close()
        conn.close()
        return redirect(url_for("reservations_list"))

    cur.execute(
        """
        SELECT COALESCE(SUM(amount), 0) as total_paid
        FROM payments
        WHERE reservation_id = %s
    """,
        (res_id,),
    )

    log_sql(
        cur,
        """
        SELECT COALESCE(SUM(amount), 0) as total_paid
        FROM payments
        WHERE reservation_id = %s
    """,
        (res_id,),
    )
    payments_result = cur.fetchone()
    total_paid = payments_result["total_paid"] if payments_result else 0
    remaining = float(reservation["total_cost"]) - float(total_paid)

    if request.method == "POST":
        amount_str = request.form.get("amount", "").strip()
        payment_method = request.form.get("payment_method", "").strip()

        if not amount_str or not payment_method:
            flash("Wypełnij wszystkie pola.", "warning")
            return render_template(
                "payment_form.html",
                reservation=reservation,
                total_paid=total_paid,
                remaining=remaining,
            )

        try:
            amount = float(amount_str)
            if amount <= 0:
                raise ValueError("Kwota musi być większa od zera")
        except ValueError:
            flash("Kwota musi być liczbą dodatnią.", "danger")
            return render_template(
                "payment_form.html",
                reservation=reservation,
                total_paid=total_paid,
                remaining=remaining,
            )

        try:
            cur.execute(
                "CALL process_payment(%s, %s, %s)", (res_id, amount, payment_method)
            )
            log_sql(
                cur,
                "CALL process_payment(%s, %s, %s)",
                (res_id, amount, payment_method),
            )
            conn.commit()
            flash(
                f"Płatność {amount:.2f} PLN ({payment_method}) zarejestrowana pomyślnie.",
                "success",
            )
            cur.close()
            conn.close()
            return redirect(url_for("reservations_list"))
        except psycopg2.errors.RaiseException as e:
            flash(f"Błąd płatności: {e}", "danger")
            conn.rollback()
        except Exception as e:
            flash(f"Błąd bazy danych: {e}", "danger")
            conn.rollback()

    cur.close()
    conn.close()
    return render_template(
        "payment_form.html",
        reservation=reservation,
        total_paid=total_paid,
        remaining=remaining,
    )


if __name__ == "__main__":
    if not hasattr(Config, "SECRET_KEY"):
        print("UWAGA: Brak SECRET_KEY w config.py! Używam domyślnego.")
        app.secret_key = "super_secret_key_dev"
    app.run(debug=True)
