# git-2-builds-ci 
Automatizace integrace do buildů


## Účel
1. Integrace vybraných commitů z feature větví do build větví (test build / master build)
    - vhodné především pro urychlení integrace commitů s drobnými změnami, rozsáhlejší změny jsou problematické, protože nelze snadno vyřešit konflikty
2. Rebase build větví (test build / master build) do hlavní test/master větve

## Prerekvizity na lokálním počítači
1. Prostředí pro vykonávání bash skriptu
  - Linux: funguje obvykle na každém systému
  - Windows: zavést emulátor unixového prostředí na Windows - Windows Subsystem for Linux, Cygwin aj.

## Pokyny před spuštěním
1. adekvátně doplnit úvodní proměnné označené TODO
2. nejde-li skript spustit, zkontrolovat odřádkování (musí být LF, Git je mohl přepsat na CRLF)

##   Použití
`bash integrace.sh -h`            zobrazí kompletní nápovědu

