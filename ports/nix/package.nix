{ lib
, buildNpmPackage
, python3
, makeWrapper
, sanoid
}:

let
  pname = "webzfs";
  # Derive the package version from upstream pyproject.toml so it remains
  # the single source of truth for the WebZFS version.
  version = (lib.importTOML ../../pyproject.toml).tool.poetry.version;
  src = ./../..;

  # Python dependencies derived from upstream requirements.txt.
  # Version pins are intentionally relaxed: nixpkgs resolves its own
  # versions, and the exact pins from Poetry cannot be satisfied across
  # the nixpkgs package set.
  #
  # ecdsa is intentionally omitted: python-jose falls back to the
  # cryptography backend, and ecdsa is flagged insecure in nixpkgs.
  pythonDeps = python3Packages: with python3Packages; [
    annotated-doc
    annotated-types
    anyio
    bcrypt
    cffi
    click
    colorama
    croniter
    cryptography
    fastapi
    gunicorn
    h11
    humanize
    idna
    invoke
    jinja2
    markdown-it-py
    markupsafe
    mdurl
    packaging
    paramiko
    psutil
    pyasn1
    pycparser
    pydantic
    pydantic-core
    pydantic-settings
    pygments
    pynacl
    python-dateutil
    python-dotenv
    python-jose
    python-multipart
    python-pam
    rich
    rsa
    shellingham
    six
    starlette
    typer
    typing-extensions
    typing-inspection
    uvicorn
  ];

  pythonEnv = python3.withPackages pythonDeps;
in

buildNpmPackage {
  inherit pname version src;

  # Compute the real hash by running:
  #   nix-shell -p nix-prefetch-npm-deps --run 'nix-prefetch-npm-deps package-lock.json'
  # then replace lib.fakeHash with the output.
  npmDepsHash = "sha256-Aq8YnyZjo30ADDFVirt//YzNh5uB2N1WAJt2q7KyvrI=";

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ pythonEnv ];

  # Add the nix store path for sanoid and syncoid to the paths list
  postPatch = ''
    file=$(find . -path "*/services/sanoid.py" -type f)
    if [ -n "$file" ]; then
      substituteInPlace "$file" \
        --replace-fail "COMMON_PATHS = [" "COMMON_PATHS = [
          '${sanoid}/bin/sanoid',
          '${sanoid}/bin/syncoid',"
    fi
  '';

  buildPhase = ''
    runHook preBuild
    npm run build:css
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/webzfs
    cp -r . $out/opt/webzfs/

    # Create a default .env from the example so the application can start.
    # This will be overwritten at runtime by the NixOS module or user config.
    cp $out/opt/webzfs/.env.example $out/opt/webzfs/.env

    mkdir -p $out/bin
    makeWrapper ${pythonEnv}/bin/gunicorn $out/bin/webzfs \
      --set PYTHONPATH "$out/opt/webzfs" \
      --add-flags "-c $out/opt/webzfs/config/gunicorn.conf.py"

    runHook postInstall
  '';

  meta = with lib; {
    description = "WebZFS - Web-based ZFS management interface";
    homepage = "https://github.com/webzfs/webzfs";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "webzfs";
  };
}
