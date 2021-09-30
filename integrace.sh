#!/bin/bash

chyba () {
  echo "$1" 1>&2
  exit 1
}

nacti_vychozi_buildy() {
  for TYP_BUILDU in "${PORADI_BUILDU[@]}"; do
    local PROMENNA_BUILDU POSLEDNI_BUILD
    if [[ "$TYP_BUILDU" == "test" ]]; then
      PROMENNA_BUILDU="TEST_BUILD";
    else
      PROMENNA_BUILDU="MASTER_BUILD";
    fi
    
    # xargs : odstraní mezery
    # tr    : obnoví odřádkování, které xargs smazal
    # sed   : najde větev origin/master_20201106_1, vrátí master_20201106_1
    POSLEDNI_BUILD=$(git branch -r \
      | xargs \
      | tr " " "\n" \
      | sed -n 's/^'"$REPO_VZDALENE\/\($TYP_BUILDU"'_[0-9]\{8\}_[0-9]\)$/\1/p' \
      | sort -r \
      | head -n 1)
    if [[ ! -z "$POSLEDNI_BUILD" ]]; then
      eval "$PROMENNA_BUILDU"'=$POSLEDNI_BUILD'
    fi
  done
}

nacti_argumenty() {
  while getopts t:m:pruhn VOLBA; do
    case "$VOLBA" in
      t)        # zda integrovat do test buildu, název test buildu
        if [[ ! -z "$OPTARG" ]]; then TEST_BUILD="$OPTARG"; fi
        BUILDY+=([test]="$TEST_BUILD")
        ;;
      m)        # zda integrovat do master buildu, název master buildu
        if [[ ! -z "$OPTARG" ]]; then MASTER_BUILD="$OPTARG"; fi
        BUILDY+=([master]="$MASTER_BUILD")
        ;;
      p)        # viz VYPSAT_MASKU
        VYPSAT_MASKU=false
        ;;
      r)        # viz ROZSAH_COMMITU
        ROZSAH_COMMITU=true
        ;;
      u)
        REBASE=true
        ;;
      n)
        VYTVORIT_NOVY_BUILD=true
        ;;
      h)
        echo "$0 - příklady použití:"
        cat <<EOF
$ bash integrace.sh <commit>                                # integrace do výchozího master a test buildu
$ bash integrace.sh -t "" <commit>                          # integrace do výchozího test buildu
$ bash integrace.sh -m "" <commit>                          # integrace do výchozího master buildu
$ bash integrace.sh -t "test_20201106_1" <commit>           # integrace do určeného test buildu
$ bash integrace.sh <commit1> <commit2> ...                 # integrace více commitů
$ bash integrace.sh -r <commit1> <commit2>                  # integrace rozsahu commitů
$ bash integrace.sh -u                                      # rebase test/master buildu do hlavní test/master větve
$ bash integrace.sh -u -n                                   # rebase test/master buildu do hlavní test/master větve a vytvoření nového buildu na hlavní větvi
EOF
        exit 0
        ;;
      \?)
        echo "Zadán nepovolený parametr." 1>&2
        exit 1
        ;;
    esac
  done

  # nebyly-li zadány žádné buildy v parametrech, použijeme všechny
  if [[ "${#BUILDY[@]}" -eq "0" ]]; then
    BUILDY+=([test]="$TEST_BUILD" [master]="$MASTER_BUILD")
  fi

  # zbylé vstupní argumenty jsou seznam commitů
  shift $(($OPTIND-1))
  COMMITY=("$@")                          # kopie pole

  if ! $REBASE; then
    if $ROZSAH_COMMITU && [[ "${#COMMITY[@]}" -ne 2 ]]; then chyba "Musí být zadány právě 2 commity, protože se integruje rozsah commitů."
    elif [[ "${#COMMITY[@]}" -lt 1 ]]; then chyba "Nebyly zadány žádné commity k integraci."; fi
  
    _zkontroluj_rozsah_commitu
  fi
}

proved_integraci() {
  pushd "$REPO_APP_NASAZENI" > /dev/null
  BRANCH_APP_NASAZENI=$(git branch --show-current)

  # Cygwin nenačítá globální .gitconfig z %USERPROFILE%, je tedy nutné ručně nastavit údaje
  git config --global user.name "$USER_NAME"
  git config --global user.email "$USER_EMAIL"

  EXISTUJI_ZMENY=$(git status --porcelain --untracked-files=no | sed 1q | wc -l)
  
  if ! $PRESKOCIT_GIT_PRIKAZY && [[ "$EXISTUJI_ZMENY" -ne "0" ]]; then
    git stash || chyba "Chyba: git stash"
  fi

  # i=0;
  for TYP_BUILDU in "${PORADI_BUILDU[@]}"; do
    BUILD="${BUILDY[$TYP_BUILDU]}"
    if [[ ! -z "$BUILD" ]]; then
      # if [[ "$i" -gt 0 ]]; then read -p "Pokračujte stiskem ENTER"; fi
      if $REBASE; then
        _rebase "$BUILD" "$TYP_BUILDU"
        read -p "Pokračujte stisknutím ENTER (worktree poté bude změněn)";
      else
        _cherry_pick "$BUILD" "$TYP_BUILDU"
        _aktualizuj_branch_git "$BUILD"
        read -p "Jakmile budou změny nasazeny, pokračujte stisknutím ENTER (worktree poté bude změněn)";
      fi
      # ((i++))
    fi
  done

  _cleanup
  echo "Integrace byla úspěšně dokončena."
  popd > /dev/null
}

zkontroluj_konflikt_vetvi() {
  pushd "$REPO_APP" > /dev/null
  local BRANCH_APP=$(git branch --show-current)
  local VETVE;
  
  if $REBASE; then VETVE=("${PORADI_BUILDU[@]}")
  else VETVE=("${BUILDY[@]}"); fi
  
  for VETEV in "${VETVE[@]}"; do
    if [[ "$BRANCH_APP" == "$VETEV" ]]; then
      echo "V repozitáři $REPO_APP je přepnuta větev buildu $VETEV. Před zahájením integrace ji přepněte na jinou větev." 1>&2
      exit 1
    fi
  done
  popd > /dev/null
}

_zkontroluj_rozsah_commitu() {
  local SHA_COMMITU
  pushd "$REPO_APP" > /dev/null
  if $ROZSAH_COMMITU; then
    SHA_COMMITU=$(git log "${COMMITY[0]}^".."${COMMITY[1]}" --pretty=format:"%H")
    if [[ "$?" -ne "0" ]]; then chyba "Byl zadán neplatný rozsah commitů."
    else
      echo "Budou integrovány následující commity:"
      echo "$SHA_COMMITU"
    fi
  fi
  popd > /dev/null
}

_cleanup() {
  if ! $PRESKOCIT_GIT_PRIKAZY; then
    git checkout "$BRANCH_APP_NASAZENI" || chyba "Chyba: git checkout"
    if [[ "$EXISTUJI_ZMENY" -ne "0" ]]; then
      git stash pop || chyba "Chyba: git stash pop"
    fi
  fi
}

_aktualizuj_branch_git() {
  local BUILD="$1"
  local SOUBOR="branch.git"
  if [[ ! -f "$SOUBOR" ]]; then echo "$BUILD" > "$SOUBOR"
  else
    CISLO_AKTUALIZACE=$(sed -n '1 s/^'"$BUILD"'-\([0-9]\+\)/\1/p' "$SOUBOR")
    if [[ ! -z "$CISLO_AKTUALIZACE" ]]; then ((CISLO_AKTUALIZACE++))
    else CISLO_AKTUALIZACE=1; fi
    echo "${BUILD}-${CISLO_AKTUALIZACE}" > "$SOUBOR"
  fi
}

_cherry_pick() {
  local BUILD="$1";
  local TYP_BUILDU="$2"
  
  if ! $PRESKOCIT_GIT_PRIKAZY; then
    git checkout "$BUILD" || chyba "Chyba: git checkout"
  fi
  local HASH_PUVODNI=$(git rev-parse HEAD)
  if ! $PRESKOCIT_GIT_PRIKAZY; then
    git pull "$REPO_VZDALENE" "$BUILD" || chyba "Chyba: git pull"
    
    if $ROZSAH_COMMITU; then git cherry-pick -Xignore-space-change "${COMMITY[0]}^".."${COMMITY[1]}"
    else git cherry-pick -Xignore-space-change "${COMMITY[@]}"; fi
  fi
  
  if [[ "$?" -eq "0" ]]; then
    if ! $PRESKOCIT_GIT_PRIKAZY; then
      git push "$REPO_VZDALENE" "$BUILD" || chyba "Chyba: git push"
    fi
    local HASH_NOVY=$(git rev-parse HEAD)
    local ZMENENE_SOUBORY=$(git diff --name-only "$HASH_PUVODNI" "$HASH_NOVY")
    
    echo "Integrace do buildu $BUILD proběhla úspěšně. Následuje výpis změněných souborů."
    if $VYPSAT_MASKU; then php "${REPO_APP}servis/soubory_k_nasazeni/index.php" "$TYP_BUILDU" "$ZMENENE_SOUBORY"
    else echo "$ZMENENE_SOUBORY"; fi
  else
    echo "Cherry pick do buildu $BUILD se nezdařil, patrně vznikl konflikt. Chcete manuálně vyřešit konflikt, nebo vrátit větev buildu do původního stavu a ukončit integraci? (y/n)"
    read ODPOVED
    if [[ "$ODPOVED" == "y" ]]; then
      echo "Proveďte opravy a poté stiskněte Ctrl+D."
      bash -i
    else
      if ! $PRESKOCIT_GIT_PRIKAZY; then
        git cherry-pick --abort || chyba "Chyba: git cherry-pick --abort"
        git reset --hard "$HASH_PUVODNI" || chyba "Chyba: git reset"
      fi
      _cleanup
      echo "Větev buildu byla vrácena do původního stavu." 1>&2
      exit 1  
    fi
  fi
}

_rebase() {
  local BUILD="$1";
  local TYP_BUILDU="$2"
  local HLAVNI_VETEV="$TYP_BUILDU"              # test/master
  local NAZEV_TAGU="${BUILD::-2}"               # master_20201106_1 -> master_20201106
  
  if ! $PRESKOCIT_GIT_PRIKAZY; then
    git checkout "$HLAVNI_VETEV" || chyba "Chyba: git checkout"
    git pull "$REPO_VZDALENE" "$HLAVNI_VETEV" || chyba "Chyba: git pull"
    git fetch "$REPO_VZDALENE" || chyba "Chyba: git fetch"
    
    git rebase "$REPO_VZDALENE/$BUILD" || chyba "Chyba: git rebase"
    git tag "$NAZEV_TAGU" || chyba "Chyba: git tag"
    git push --tags "$REPO_VZDALENE" "$HLAVNI_VETEV" || chyba "Chyba: git push"
  fi
  echo "Rebase buildu $BUILD do hlavní věve $HLAVNI_VETEV proběhl úspěšně."
  
  if $VYTVORIT_NOVY_BUILD; then
    local DATUM=$(date +'%Y%m%d')
    local NOVY_BUILD="${TYP_BUILDU}_${DATUM}_1"
    
    if ! $PRESKOCIT_GIT_PRIKAZY; then
      git branch "$NOVY_BUILD" || chyba "Chyba: git branch"
      git checkout "$NOVY_BUILD" || chyba "Chyba: git checkout"
      git push "$REPO_VZDALENE" "$NOVY_BUILD" || chyba "Chyba: git push"
    fi
    
    echo "Vytvoření nového buildu $NOVYBUILD proběhlo úspěšně."
  fi
}


# TODO: měnitelné proměnné ukládat načítat ze samostatného souboru
USER_NAME="My Name"                             # TODO
USER_EMAIL="my.name@example.com"                # TODO
REPO_VZDALENE='origin'
REPO_APP_NASAZENI='D:/app_nasazeni/'            # TODO: repozitář, kam se integruje
REPO_APP='D:/Weby/app/'                         # TODO: další složka (worktree) repozitáře (nesmí obsahovat stejnou větev jako REPO_APP_NASAZENI)
TEST_BUILD="test_20201106_1"                    # výchozí test build (nově se načítá automaticky v nacti_vychozi_buildy)
MASTER_BUILD="master_20201106_1"                # výchozí master build (nově se načítá automaticky v nacti_vychozi_buildy)
VYPSAT_MASKU=true                               # zda vypsat jen seznam změněných souborů, nebo tento seznam zpracovat skriptem soubory_k_nasazeni
ROZSAH_COMMITU=false                            # zda integrovat všechny commity v zadaném rozsahu (jako argument musí být zadány 2 commity)
VYTVORIT_NOVY_BUILD=false                       # zda po dokončení rebase vytvořit na hlavní větvi nový build
REBASE=false                                    # zda namísto integrace nových commitů do test/master buildu provést rebase test/master buildu do hlavní test/master větve
declare -a COMMITY                              # pole commitů, které se integrují
declare -A BUILDY                               # pole buildů, do kterých se integruje
declare -a PORADI_BUILDU
PORADI_BUILDU=("test" "master")                 # pořadí nelze definovat v rámci BUILDY, protože asoc. pole má pořadí klíčů vždy abecední
PRESKOCIT_GIT_PRIKAZY=false                     # jen pro testování



nacti_vychozi_buildy

nacti_argumenty "$@"

zkontroluj_konflikt_vetvi

proved_integraci

exit 0
