<?php

use MyAAC\Models\BoostedCreature;
use MyAAC\Models\PlayerOnline;
use MyAAC\Models\Account;
use MyAAC\Models\Player;
use MyAAC\RateLimit;

require_once 'common.php';
require_once SYSTEM . 'functions.php';
require_once SYSTEM . 'init.php';
require_once SYSTEM . 'status.php';



# error function
function sendError($message, $code = 3){
    $ret = [];
    $ret['errorCode'] = $code;
    $ret['errorMessage'] = $message;
    die(json_encode($ret));
}

// -------- Secure session token helpers (stateless, HMAC signed) --------
// Uses a server-side secret that MUST NOT be exposed to clients.
// Configure via env API_SECRET or MyAAC setting core.api_secret.
function api_secret()
{
    $secret = getenv('API_SECRET');
    if (!$secret && function_exists('setting')) {
        $secret = setting('core.api_secret');
    }
    if (!$secret) {
        // Fallback for dev; override in production via env/setting
        $secret = 'CHANGE_ME_SECRET';
    }
    return (string)$secret;
}

// Optional site API key (when configured, login requests must include a matching apiKey)
function site_api_key()
{
    $key = getenv('SITE_API_KEY');
    if (!$key && function_exists('setting')) {
        $key = setting('core.api_key');
    }
    // Fallback para chave padrão fornecida pelo cliente
    if (!$key) {
        $key = '6f8d9c2a1b7e4d3f9a0c5e7b2d6f1a3c8e9b0d4f2a6c7e5b1d3f9a2c4e6b8d0f';
    }
    return (string)$key;
}

function b64url_encode($data) { return rtrim(strtr(base64_encode($data), '+/', '-_'), '='); }
function b64url_decode($data) { return base64_decode(strtr($data, '-_', '+/')); }

function generateSessionToken(int $accountId, string $ip, int $ttlSeconds = 900)
{
    $exp = time() + max(60, $ttlSeconds);
    $payload = $accountId . ':' . $exp . ':' . $ip;
    $sig = hash_hmac('sha256', $payload, api_secret());
    return b64url_encode($payload . ':' . $sig);
}

// -------- Request HMAC verification --------
// Client signs canonical string: method\npath\ntimestamp\nnonce\nbodySha256Hex using the site API key
function verify_request_hmac(?string $rawBody = null)
{
    $sig = $_SERVER['HTTP_X_API_SIGNATURE'] ?? '';
    $ts = $_SERVER['HTTP_X_API_TIMESTAMP'] ?? '';
    $nonce = $_SERVER['HTTP_X_API_NONCE'] ?? '';
    $bodyHash = $_SERVER['HTTP_X_API_BODY_HASH'] ?? '';
    if ($sig === '' || $ts === '' || $nonce === '' || $bodyHash === '') {
        return false;
    }
    if (!ctype_digit((string)$ts)) { return false; }
    $now = time();
    // 2 minutes clock skew window
    if (abs($now - (int)$ts) > 120) { return false; }
    // Basic nonce format check (hex, length 32)
    if (!preg_match('/^[0-9a-f]{32}$/', strtolower($nonce))) { return false; }

    $method = $_SERVER['REQUEST_METHOD'] ?? 'POST';
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
    $raw = $rawBody ?? (file_get_contents('php://input') ?? '');
    $calcHash = hash('sha256', $raw);
    if (!hash_equals($calcHash, strtolower($bodyHash))) { return false; }

    $canonical = $method . "\n" . $path . "\n" . $ts . "\n" . strtolower($nonce) . "\n" . strtolower($bodyHash);
    $expected = hash_hmac('sha256', $canonical, site_api_key());
    return hash_equals(strtolower($expected), strtolower($sig));
}

// Verifies and returns accountId on success; returns 0 on failure
function verifySessionToken(?string $token)
{
    if (!$token || !is_string($token)) { return 0; }
    $raw = b64url_decode($token);
    if (!$raw) { return 0; }
    $parts = explode(':', $raw);
    if (count($parts) !== 4) { return 0; }
    [$aid, $exp, $ipBound, $sig] = $parts;
    if (!ctype_digit((string)$aid) || !ctype_digit((string)$exp)) { return 0; }
    if ((int)$exp < time()) { return 0; }
    $expected = hash_hmac('sha256', $aid . ':' . $exp . ':' . $ipBound, api_secret());
    if (!hash_equals($expected, $sig)) { return 0; }
    // Bind to current request IP to reduce replay from other hosts
    $reqIp = get_browser_real_ip();
    if ($ipBound !== $reqIp) { return 0; }
    return (int)$aid;
}

// Simple application-level rate limiting helper per endpoint
function applyRateLimit($scope, $limit, $banMinutes) {
    $ip = get_browser_real_ip();
    $limiter = new RateLimit($scope, (int)$limit, (int)$banMinutes);
    // enable for all scopes in API
    $limiter->enabled = true;
    $limiter->load();
    if ($limiter->exceeded($ip)) {
        sendError('Too many requests. Please wait and try again later.');
    }
    // record attempt for current request
    $limiter->increment($ip);
}

# event schedule function
function parseEvent($table1, $date, $table2)
{
	if ($table1) {
		if ($date) {
			if ($table2) {
				$date = $table1->getAttribute('startdate');
				return date_create("{$date}")->format('U');
			} else {
				$date = $table1->getAttribute('enddate');
				return date_create("{$date}")->format('U');
			}
		} else {
			foreach($table1 as $attr) {
				if ($attr) {
					return $attr->getAttribute($table2);
				}
			}
		}
	}
	return 'error';
}

$rawBody = file_get_contents('php://input');
$request = json_decode($rawBody);
$action = $request->type ?? '';

// Basic request hardening (keep loose to avoid breaking dev clients)
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendError('Invalid request method.');
}
if (isset($_SERVER['CONTENT_LENGTH']) && (int)$_SERVER['CONTENT_LENGTH'] > 8192) {
    sendError('Payload too large.');
}
if (!is_object($request)) {
    sendError('Malformed JSON payload.');
}

// Exigir HMAC válido em todas as chamadas (assina método, caminho, timestamp, nonce e hash do corpo)
if (!verify_request_hmac($rawBody)) {
    sendError('Assinatura HMAC inválida.');
}

/** @var OTS_Base_DB $db */
/** @var array $config */

switch ($action) {
    case 'register':
        // Limit abusive account creations (per IP)
        applyRateLimit('register_attempts', 5, 30);
        // Create account via client JSON request
        $email = isset($request->email) ? trim($request->email) : '';
        $password = isset($request->password) ? (string)$request->password : '';

        // Basic validations
        if (strlen($email) > 254) {
            die(json_encode(['errors' => ['email' => ['E-mail muito longo.']]]));
        }
        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            die(json_encode(['errors' => ['email' => ['E-mail inválido.']]]));
        }
        if (strlen($password) > 128) {
            die(json_encode(['errors' => ['password' => ['Senha muito longa.']]]));
        }
        if (strlen($password) < 6) {
            die(json_encode(['errors' => ['password' => ['Senha deve ter pelo menos 6 caracteres.']]]));
        }

        // Email uniqueness
        $exists = Account::where('email', $email)->first();
        if ($exists) {
            die(json_encode(['errors' => ['email' => ['Este e-mail já está em uso.']]]));
        }

        // Generate unique account name from email local part
        $local = preg_replace('/[^a-zA-Z0-9]/', '', explode('@', $email)[0]);
        $nameBase = $local !== '' ? $local : 'user';
        $name = $nameBase;
        $suffix = 0;
        while (Account::where('name', $name)->first()) {
            $suffix++;
            $name = $nameBase . $suffix;
        }

        // Handle salt if schema supports it
        $salt = '';
        if (function_exists('fieldExist') && fieldExist('salt', 'accounts')) {
            $salt = substr(sha1(random_bytes(16)), 0, 10);
        }

        // Hash password using MyAAC encrypt helper
        $passHash = encrypt(($salt ? $salt : '') . $password);

        // Create account
        $acc = new Account();
        $acc->email = $email;
        $acc->name = $name;
        $acc->password = $passHash;
        if ($salt) { $acc->salt = $salt; }
        // Optional defaults
        if (property_exists($acc, 'premdays')) { $acc->premdays = 0; }
        if (property_exists($acc, 'email_verified')) { $acc->email_verified = 0; }
        $acc->save();

        die(json_encode(['message' => 'Conta criada com sucesso!', 'status' => true]));

	case 'cacheinfo':
		$playersonline = PlayerOnline::count();
		die(json_encode([
			'playersonline' => $playersonline,
			'twitchstreams' => 0,
			'twitchviewer' => 0,
			'gamingyoutubestreams' => 0,
			'gamingyoutubeviewer' => 0
		]));

	case 'eventschedule':
		$eventlist = [];
		$file_path = config('server_path') . 'data/XML/events.xml';
		if (!file_exists($file_path)) {
			die(json_encode([]));
		}
		$xml = new DOMDocument;
		$xml->load($file_path);
		$tmplist = [];
		$tableevent = $xml->getElementsByTagName('event');

		foreach ($tableevent as $event) {
			if ($event) { $tmplist = [
			'colorlight' => parseEvent($event->getElementsByTagName('colors'), false, 'colorlight'),
			'colordark' => parseEvent($event->getElementsByTagName('colors'), false, 'colordark'),
			'description' => parseEvent($event->getElementsByTagName('description'), false, 'description'),
			'displaypriority' => intval(parseEvent($event->getElementsByTagName('details'), false, 'displaypriority')),
			'enddate' => intval(parseEvent($event, true, false)),
			'isseasonal' => getBoolean(intval(parseEvent($event->getElementsByTagName('details'), false, 'isseasonal'))),
			'name' => $event->getAttribute('name'),
			'startdate' => intval(parseEvent($event, true, true)),
			'specialevent' => intval(parseEvent($event->getElementsByTagName('details'), false, 'specialevent'))
				];
			$eventlist[] = $tmplist; } }
		die(json_encode(['eventlist' => $eventlist, 'lastupdatetimestamp' => time()]));

	case 'boostedcreature':
		$clientVersion = (int)setting('core.client');

		// 13.40 and up
		if ($clientVersion >= 1340) {
			$creatureBoost = $db->query("SELECT * FROM " . $db->tableName('boosted_creature'))->fetchAll();
			$bossBoost     = $db->query("SELECT * FROM " . $db->tableName('boosted_boss'))->fetchAll();
			die(json_encode([
				'boostedcreature' => true,
				'creatureraceid'  => intval($creatureBoost[0]['raceid']),
				'bossraceid'      => intval($bossBoost[0]['raceid'])
			]));
		}

		// lower clients
		$boostedCreature = BoostedCreature::first();
		die(json_encode([
			'boostedcreature' => true,
			'raceid' => $boostedCreature->raceid
		]));

    case 'login':

		$port = $config['lua']['gameProtocolPort'];

		// default world info
		$world = [
			'id' => 0,
			'name' => $config['lua']['serverName'],
			'externaladdress' => $config['lua']['ip'],
			'externalport' => $port,
			'externaladdressprotected' => $config['lua']['ip'],
			'externalportprotected' => $port,
			'externaladdressunprotected' => $config['lua']['ip'],
			'externalportunprotected' => $port,
			'previewstate' => 0,
			'location' => 'BRA', // BRA, EUR, USA
			'anticheatprotection' => false,
			'pvptype' => array_search($config['lua']['worldType'], ['pvp', 'no-pvp', 'pvp-enforced']),
			'istournamentworld' => false,
			'restrictedstore' => false,
			'currenttournamentphase' => 2
		];

		$characters = [];

		$inputEmail = $request->email ?? false;
		$inputAccountName = $request->accountname ?? false;
		$inputToken = $request->token ?? false;

		$account = Account::query();
		if ($inputEmail != false) { // login by email
			$account->where('email', $inputEmail);
		}
		else if($inputAccountName != false) { // login by account name
			$account->where('name', $inputAccountName);
		}

		$account = $account->first();

		$ip = get_browser_real_ip();
		$limiter = new RateLimit('failed_logins', setting('core.account_login_attempts_limit'), setting('core.account_login_ban_time'));
		$limiter->enabled = setting('core.account_login_ipban_protection');
		$limiter->load();

		$ban_msg = 'A wrong account, password or secret has been entered ' . setting('core.account_login_attempts_limit') . ' times in a row. You are unable to log into your account for the next ' . setting('core.account_login_ban_time') . ' minutes. Please wait.';
		if (!$account) {
			$limiter->increment($ip);
			if ($limiter->exceeded($ip)) {
				sendError($ban_msg);
			}

			sendError(($inputEmail != false ? 'Email' : 'Account name') . ' or password is not correct.');
		}

		$current_password = encrypt((USE_ACCOUNT_SALT ? $account->salt : '') . $request->password);
		if (!$account || $account->password != $current_password) {
			$limiter->increment($ip);
			if ($limiter->exceeded($ip)) {
				sendError($ban_msg);
			}

			sendError(($inputEmail != false ? 'Email' : 'Account name') . ' or password is not correct.');
		}

		$accountHasSecret = false;
		if (fieldExist('secret', 'accounts')) {
			$accountSecret = $account->secret;
			if ($accountSecret != null && $accountSecret != '') {
				$accountHasSecret = true;
				if ($inputToken === false) {
					$limiter->increment($ip);
					if ($limiter->exceeded($ip)) {
						sendError($ban_msg);
					}
					sendError('Submit a valid two-factor authentication token.', 6);
				} else {
					require_once LIBS . 'rfc6238.php';
					if (TokenAuth6238::verify($accountSecret, $inputToken) !== true) {
						$limiter->increment($ip);
						if ($limiter->exceeded($ip)) {
							sendError($ban_msg);
						}

						sendError('Two-factor authentication failed, token is wrong.', 6);
					}
				}
			}
		}

		$limiter->reset($ip);
		if (setting('core.account_mail_verify') && $account->email_verified !== 1) {
			sendError('You need to verify your account, enter in our site and resend verify e-mail!');
		}

		// common columns
		$columns = 'id, name, level, sex, vocation, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons';

		if (fieldExist('isreward', 'accounts')) {
			$columns .= ', isreward';
		}

		if (fieldExist('istutorial', 'accounts')) {
			$columns .= ', istutorial';
		}

		$players = Player::where('account_id', $account->id)->notDeleted()->selectRaw($columns)->get();
		if($players && $players->count()) {
			$highestLevelId = $players->sortByDesc('experience')->first()->getKey();

			foreach ($players as $player) {
				$characters[] = create_char($player, $highestLevelId);
			}
		}

		/*
		 * not needed anymore?
		if (fieldExist('premdays', 'accounts') && fieldExist('lastday', 'accounts')) {
			$save = false;
			$timeNow = time();
			$premDays = $account->premdays;
			$lastDay = $account->lastday;
			$lastLogin = $lastDay;

			if ($premDays != 0 && $premDays != PHP_INT_MAX) {
				if ($lastDay == 0) {
					$lastDay = $timeNow;
					$save = true;
				} else {
					$days = (int)(($timeNow - $lastDay) / 86400);
					if ($days > 0) {
						if ($days >= $premDays) {
							$premDays = 0;
							$lastDay = 0;
						} else {
							$premDays -= $days;
							$reminder = ($timeNow - $lastDay) % 86400;
							$lastDay = $timeNow - $reminder;
						}

						$save = true;
					}
				}
			} else if ($lastDay != 0) {
				$lastDay = 0;
				$save = true;
			}
			if ($save) {
				$account->premdays = $premDays;
				$account->lastday = $lastDay;
				$account->save();
			}
		}
		*/

		$worlds = [$world];
		$playdata = compact('worlds', 'characters');

		$sessionKey = ($inputEmail !== false) ? $inputEmail : $inputAccountName; // email or account name
		$sessionKey .= "\n" . $request->password; // password
		if (!fieldExist('istutorial', 'players')) {
			$sessionKey .= "\n";
		}
		$sessionKey .= ($accountHasSecret && strlen($accountSecret) > 5) ? $inputToken : '';

		// this is workaround to distinguish between TFS 1.x and otservbr
		// TFS 1.x requires the number in session key
		// otservbr requires just login and password
		// so we check for istutorial field which is present in otservbr, and not in TFS
		if (!fieldExist('istutorial', 'players')) {
			$sessionKey .= "\n".floor(time() / 30);
		}

        $session = [
            'sessionkey' => $sessionKey,
            'lastlogintime' => 0,
            'ispremium' => $account->is_premium,
            'premiumuntil' => ($account->premium_days) > 0 ? (time() + ($account->premium_days * 86400)) : 0,
            'status' => 'active', // active, frozen or suspended
            'returnernotification' => false,
            'showrewardnews' => true,
            'isreturner' => true,
            'fpstracking' => false,
            'optiontracking' => false,
            'tournamentticketpurchasestate' => 0,
            'emailcoderequest' => false
        ];
        // Issue short-lived, IP-bound session token for site API calls
        $session['sessiontoken'] = generateSessionToken((int)$account->id, get_browser_real_ip());
        $session['sessionexpires'] = time() + 900;
        die(json_encode(compact('session', 'playdata')));

    case 'validateRegister':
        // Limit real-time validation abuse (per IP)
        applyRateLimit('validate_register', 60, 1);
        // Server-side validation for account registration fields (real-time)
        $errors = [];
		// Terms accepted
		if (isset($request->termsAccepted)) {
			$accepted = (bool)$request->termsAccepted;
			if (!$accepted) {
				$errors['termsAccepted'][] = 'Primeiro Você precisa aceitar o termos e regras.';
			}
		}

		// Email validation + uniqueness
        if (isset($request->email)) {
            $email = trim((string)$request->email);
            if ($email === '') {
                $errors['email'][] = 'Preencha este campo.';
            } else if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
                $errors['email'][] = 'E-mail não é válido.';
            } else {
                if (strlen($email) > 254) {
                    $errors['email'][] = 'E-mail muito longo.';
                }
                $exists = Account::where('email', $email)->first();
                if ($exists) {
                    $errors['email'][] = 'Este e-mail já está em uso.';
                }
            }
        }

		// Confirm email validation
		if (isset($request->confirmEmail)) {
			$confirm = trim((string)$request->confirmEmail);
			if ($confirm === '') {
				$errors['confirmEmail'][] = 'Preencha este campo.';
			} else if (isset($request->email)) {
				$email = trim((string)$request->email);
				if ($email !== $confirm) {
					$errors['confirmEmail'][] = 'O e-mail não é o mesmo.';
				}
			}
		}

		// Password rules (mirror client isValidPassword)
        if (isset($request->password)) {
            $password = (string)$request->password;
            if (trim($password) === '') {
                $errors['password'][] = 'Preencha este campo.';
            } else {
                if (strlen($password) > 128) { $errors['password'][] = 'Senha muito longa.'; }
                if (!preg_match('/[a-z]/', $password)) { $errors['password'][] = 'A senha deve conter ao menos 1 letra minúscula.'; }
                if (!preg_match('/[A-Z]/', $password)) { $errors['password'][] = 'A senha deve conter ao menos 1 letra maiúscula.'; }
                if (strlen($password) <= 8) { $errors['password'][] = 'A senha deve conter ao menos 8 caracteres.'; }
                if (!preg_match('/[\p{P}\p{S}]/u', $password)) { $errors['password'][] = 'A senha deve conter ao menos 1 caracter especial.'; }
                if (!preg_match('/\d/', $password)) { $errors['password'][] = 'A senha deve conter ao menos 1 numero.'; }
            }
        }

		// Confirm password validation
		if (isset($request->confirmPassword)) {
			$confirm = (string)$request->confirmPassword;
			if (trim($confirm) === '') {
				$errors['confirmPassword'][] = 'Preencha este campo.';
			} else if (isset($request->password)) {
				$password = (string)$request->password;
				if ($password !== $confirm) {
					$errors['confirmPassword'][] = 'Essa senha não é a mesma.';
				}
			}
		}

		if (!empty($errors)) {
			// return only errors map for real-time feedback
			die(json_encode(['errors' => $errors]));
		}

		// No errors for provided fields
		$successMessage = 'Dados válidos.';
		die(json_encode(['status' => true, 'message' => $successMessage]));
		break;

    case 'validateCharacter':
        // Limit real-time validation abuse (per IP)
        applyRateLimit('validate_character', 60, 1);
        // Require a valid session token issued at login
        $aid = verifySessionToken($request->sessionToken ?? null);
        if (!$aid) {
            // Return in the same shape the client expects for inline helper
            die(json_encode(['errors' => ['name' => ['Sessão inválida ou expirada. Faça login novamente.']]]));
        }
        // Server-side validation for character name (real-time)
        $name = isset($request->name) ? trim((string)$request->name) : '';
        $errors = [];
		if ($name === '') {
			$errors['name'][] = 'Preencha este campo.';
		} else {
			$minLength = 5; $maxLength = 14;
			if (mb_strlen($name) < $minLength || mb_strlen($name) > $maxLength) {
				$errors['name'][] = sprintf('O comprimento do nome deve estar entre %d e %d caracteres.', $minLength, $maxLength);
			}
			if (preg_match('/\s{2,}/u', $name)) {
				$errors['name'][] = 'O nome não pode conter mais de um espaço em branco consecutivo.';
			}
			if ($name === mb_strtoupper($name)) {
				$errors['name'][] = 'O nome não pode estar todo em letras maiúsculas.';
			}
			if (preg_match('/^\s|\s$/u', $name)) {
				$errors['name'][] = 'O nome não pode ter espaços em branco no início ou no final.';
			}
			// Invalid chars (including digits and common punctuation)
			if (preg_match('/[{}\|_\*\+\-\=<>0-9@#%\^&\(\)\/\\\.,:;~!\"\$]/u', $name)) {
				$errors['name'][] = 'O nome contém caracteres inválidos.';
			}
			// Only letters and spaces allowed (no accents/specials beyond letters)
			if (!preg_match('/^[\p{L}\s]+$/u', $name)) {
				$errors['name'][] = 'O nome não pode conter acentuações ou caracteres especiais.';
			}
			// Each word must start with uppercase letter
			$parts = preg_split('/\s+/', $name);
			foreach ($parts as $part) {
				if ($part === '') continue;
				if (!preg_match('/^\p{Lu}/u', $part)) {
					$errors['name'][] = 'Cada parte do nome deve começar com uma letra maiúscula.';
					break;
				}
			}
			// Uniqueness
			if (empty($errors['name'])) {
				$exists = Player::where('name', $name)->first();
				if ($exists) {
					$errors['name'][] = 'Nome de personagem já está em uso.';
				}
			}
		}

		if (!empty($errors)) {
			die(json_encode(['errors' => $errors]));
		}

		die(json_encode(['status' => true, 'message' => 'Nome válido.']));
		break;

	case 'createCharacter':
        // Limit character creation attempts (per IP)
        applyRateLimit('create_character', 10, 10);
        // Create a new character for the authenticated account
        try {
            // Require a valid session token issued at login
            $aid = verifySessionToken($request->sessionToken ?? null);
            if (!$aid) {
                die(json_encode(['status' => 'error', 'message' => 'Sessão inválida ou expirada. Faça login novamente.']));
            }
            $email = isset($request->email) ? trim($request->email) : '';
            $password = isset($request->password) ? (string)$request->password : '';
            $name = isset($request->name) ? trim($request->name) : '';
			$genderRaw = isset($request->sex) ? (string)$request->sex : 'male';
			$worldId = isset($request->worldId) ? (int)$request->worldId : 0;
            // Resolve account by session
            $account = Account::find($aid);
            if (!$account) {
                die(json_encode(['status' => 'error', 'message' => 'Conta não encontrada.']));
            }

			// Validate character name
			if ($name === '' || strlen($name) < 2 || strlen($name) > 30) {
				die(json_encode(['status' => 'error', 'message' => 'Nome inválido (2-30 caracteres).']));
			}
			if (!preg_match('/^[A-Za-z ]+$/', $name)) {
				die(json_encode(['status' => 'error', 'message' => 'Nome contém caracteres inválidos.']));
			}
			if (preg_match('/^ |  | $/', $name)) {
				die(json_encode(['status' => 'error', 'message' => 'Nome não pode começar/terminar com espaço ou ter duplo espaço.']));
			}

			// Uniqueness
			if (Player::where('name', $name)->first()) {
				die(json_encode(['status' => 'error', 'message' => 'Nome de personagem já está em uso.']));
			}

			// Gender mapping
			$genderStr = strtolower($genderRaw);
			if (is_numeric($genderStr)) {
				$sex = ((int)$genderStr) === 1 ? 1 : 0;
			} else {
				$sex = $genderStr === 'male' ? 1 : 0;
			}

			// World validation (single-world default)
			if ($worldId !== 0) {
				die(json_encode(['status' => 'error', 'message' => 'World inválido.']));
			}

            $player = new Player();
            $player->account_id = $account->id;
            $player->name = $name;
            $player->sex = $sex; // 0 female, 1 male
			// Safe defaults
			if (!isset($player->level)) { $player->level = 1; }
			if (!isset($player->vocation)) { $player->vocation = 0; }
			if (!isset($player->looktype)) { $player->looktype = ($sex === 1 ? 128 : 136); }
			if (!isset($player->lookhead)) { $player->lookhead = 0; }
			if (!isset($player->lookbody)) { $player->lookbody = 0; }
			if (!isset($player->looklegs)) { $player->looklegs = 0; }
			if (!isset($player->lookfeet)) { $player->lookfeet = 0; }
			if (!isset($player->lookaddons)) { $player->lookaddons = 0; }
			if (!isset($player->town_id)) { $player->town_id = 1; }

			if (!$player->save()) {
				die(json_encode(['status' => 'error', 'message' => 'Falha ao criar o personagem.']));
			}

			die(json_encode(['status' => 'success', 'message' => 'Personagem criado com sucesso.']));
		} catch (\Throwable $e) {
			die(json_encode(['status' => 'error', 'message' => 'Erro interno ao criar personagem.']));
		}
		break;

    case 'charactersList':
        // Retorna a lista de personagens no formato esperado pelo cliente (CharacterList)
        // Requer um token de sessão válido
        try {
            $aid = verifySessionToken($request->sessionToken ?? null);
            if (!$aid) {
                die(json_encode(['status' => 'error', 'message' => 'Sessão inválida ou expirada. Faça login novamente.']));
            }

            $columns = 'id, name, level, sex, vocation, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons';
            $players = Player::where('account_id', $aid)->notDeleted()->selectRaw($columns)->get();
            $port = $config['lua']['gameProtocolPort'];
            $worldName = $config['lua']['serverName'];
            $worldIp = $config['lua']['ip'];

            $list = [];
            if ($players && $players->count()) {
                foreach ($players as $player) {
                    $list[] = [
                        'name' => $player->name,
                        'level' => $player->level,
                        'worldName' => $worldName,
                        'worldIp' => $worldIp,
                        'worldPort' => $port,
                        'sex' => $player->sex,
                        'clan' => null,
                        'daysToDelete' => null
                    ];
                }
            }

            die(json_encode(['body' => $list]));
        } catch (\Throwable $e) {
            die(json_encode(['status' => 'error', 'message' => 'Erro ao listar personagens.']));
        }
        break;

    case 'deleteCharacter':
        // Agenda exclusão lógica imediata (soft delete) do personagem da conta
        // Requer token de sessão válido
        try {
            applyRateLimit('delete_character', 20, 2);
            $aid = verifySessionToken($request->sessionToken ?? null);
            if (!$aid) {
                die(json_encode(['status' => 'error', 'message' => 'Sessão inválida ou expirada. Faça login novamente.']));
            }
            $name = isset($request->name) ? trim((string)$request->name) : '';
            if ($name === '') {
                die(json_encode(['status' => 'error', 'message' => 'Nome do personagem é obrigatório.']));
            }

            $player = Player::where('account_id', $aid)->where('name', $name)->first();
            if (!$player) {
                die(json_encode(['status' => 'error', 'message' => 'Personagem não encontrado nesta conta.']));
            }

            // Soft delete via flag is_deleted (compatível com notDeleted())
            if (property_exists($player, 'is_deleted')) {
                if ($player->is_deleted) {
                    die(json_encode(['status' => 'error', 'message' => 'Este personagem já está excluído/oculto.']));
                }
                $player->is_deleted = 1;
                $player->save();
            } else {
                // Fallback absoluto: remover registro
                $player->delete();
            }

            die(json_encode(['status' => true, 'message' => 'Personagem excluído com sucesso.']));
        } catch (\Throwable $e) {
            die(json_encode(['status' => 'error', 'message' => 'Erro ao excluir personagem.']));
        }
        break;

    case 'cancelDeleteCharacter':
        // Cancela exclusão lógica (soft delete), restaurando visibilidade
        // Requer token de sessão válido
        try {
            applyRateLimit('cancel_delete_character', 20, 2);
            $aid = verifySessionToken($request->sessionToken ?? null);
            if (!$aid) {
                die(json_encode(['status' => 'error', 'message' => 'Sessão inválida ou expirada. Faça login novamente.']));
            }
            $name = isset($request->name) ? trim((string)$request->name) : '';
            if ($name === '') {
                die(json_encode(['status' => 'error', 'message' => 'Nome do personagem é obrigatório.']));
            }

            $player = Player::where('account_id', $aid)->where('name', $name)->first();
            if (!$player) {
                die(json_encode(['status' => 'error', 'message' => 'Personagem não encontrado nesta conta.']));
            }

            if (property_exists($player, 'is_deleted')) {
                if (!$player->is_deleted) {
                    die(json_encode(['status' => 'error', 'message' => 'Este personagem não está marcado para exclusão.']));
                }
                $player->is_deleted = 0;
                $player->save();
            } else {
                // Sem suporte a soft delete, não há como cancelar
                die(json_encode(['status' => 'error', 'message' => 'Cancelamento indisponível para este servidor.']));
            }

            die(json_encode(['status' => true, 'message' => 'Exclusão cancelada com sucesso.']));
        } catch (\Throwable $e) {
            die(json_encode(['status' => 'error', 'message' => 'Erro ao cancelar exclusão do personagem.']));
        }
        break;

	default:
		sendError("Unrecognized event {$action}.");
	break;
}

function create_char($player, $highestLevelId) {
	return [
		'worldid' => 0,
		'name' => $player->name,
		'ismale' => $player->sex === 1,
		'tutorial' => isset($player->istutorial) && $player->istutorial,
		'level' => $player->level,
		'vocation' => $player->vocation_name,
		'outfitid' => $player->looktype,
		'headcolor' => $player->lookhead,
		'torsocolor' => $player->lookbody,
		'legscolor' => $player->looklegs,
		'detailcolor' => $player->lookfeet,
		'addonsflags' => $player->lookaddons,
		'ishidden' => $player->is_deleted,
		'istournamentparticipant' => false,
		'ismaincharacter' => $highestLevelId === $player->getKey(),
		'dailyrewardstate' => $player->isreward ?? 0,
		'remainingdailytournamentplaytime' => 0
	];
}
