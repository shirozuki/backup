#!/bin/bash

set -e

if [[ ! $(which scp) ]]; then
    echo 'Ten skrypt do prawidłowego działania potrzebuje programu scp, który nie został'
    echo 'znaleziony na komputerze. Aby kontynuować proszę zainstalować program scp.'
    exit 0;
fi

if [[ ! $(which realpath) ]]; then
    echo 'Ten skrypt do prawidłowego działania potrzebuje programu realpath, który nie został'
    echo 'znaleziony na komputerze. Aby kontynuować proszę zainstalować program realpath.'
    exit 0;
fi

list=/home/$USER/.backup.lst

#Zmienne sterujące przebiegiem skryptu
run_add=0
run_remove=0
run_backup=0
run_update=0

function f_print_lst
{
    f_check_if_list_exists
    echo "#----------------------------#"
    echo " Lista elementów .backup.lst:"
    echo ""
    cat $list
    echo "#----------------------------#"
    exit 0;
}

function f_help
{
    echo "Skrypt wykona kopię zapasową plików."
    echo "-*- Artur Dobrowolski -*-"
    echo
    echo "Użytkowanie:"
    echo "-h | wyświetla ten ekran pomocy"
    echo "-a | dodaje wskazaną ścieżkę do pliku .backup.lst"
    echo "-r | usuwa wskazaną ścieżkę z pliku .backup.lst"
    echo "-p | wyświetla zawartość pliku .backup.lst"
    echo "-b | wykonuje kopię plików na zdalnym serwerze"
    echo "     Opcja -b wykona kopię zapasową w katalogu domowym użytkownika zdalnego."
    echo "     Aby wskazać dokładną ścieżkę należy skorzystać ze składni: backup.sh -b abc/xyz"
    echo "     W takim przypadku kopia zapasowa zostanie utworzona pod ścieżką: ~/abc/xyz/YYYY-MM-DD-hh-mm-ss/"
    echo "-u | wykona kopię tylko tych elementów, które zostały utworzone/zmodyfikowane później niż ostatni wykonany"
    echo "     backup znajdujący się pod tą samą ścieżką."
    echo "     Opcja -u wykona kopię zapasową w katalogu domowym użytkownika zdalnego."
    echo "     Aby wskazać dokładną ścieżkę należy skorzystać ze składni: backup.sh -u abc/xyz"
    echo "     W takim przypadku kopia zapasowa zostanie utworzona pod ścieżką: ~/abc/xyz/YYYY-MM-DD-hh-mm-ss/"
    echo ""
    echo "W przypadku dużej desynchronizacji czasu systemowego komputera lokalnego i zdalnego opcja update nie będzie działała prawidłowo."
    echo "-------------------------------------------------------------------------------------------------------"
    echo "<< Nawiązywanie połączenia >>"
    echo ""
    echo "Skrypt zakłada, że połączenie SSH na komputerze jest już skonfigurowane za pomocą kluczy RSA."
    echo "Aby zdefiniować nazwę użytkownika zdalnego należy stworzyć zmienną środowiskową o nazwie _user, np."
    echo " - export _user=my_login -"
    echo "Aby zdefiniować nazwę hosta należy stworzyć zmienną środowiskową o nazwie _host, np."
    echo " - export _host=my_host - "
    echo ""
    exit 0;
}

function f_check_if_list_exists
{
if [[ ! -f $list ]]; then
    echo "Plik backup.lst nie istnieje!"
    echo "Aby utworzyć, proszę wywołać skrypt z parametrem -a i dodać jakąś ścieżkę."
    exit 0;
fi
}

function f_check_list_validity
{
h_file=`cat $list`
for line in $h_file ; do
    if [[ ! -d "$line" && ! -f "$line" ]]; then
    echo "Plik .backup.lst zawiera błędy!"
    echo "Element "$line" nie jest poprawną ścieżką"
    echo "Aby kontynuować proszę usunąć element "$line" z pliku .backup.lst"
    exit 0;
    fi
done
}

function f_update
{
f_check_if_list_exists
f_check_list_validity

dir_name=`date +%F-%H-%M-%S`
echo "<< Nawiązuję połączenie >>"

if ! `ssh $_user@$_host "cd ~/$path_update" 2> /dev/null`; then
    echo "Brak podanej ścieżki na komputerze zdalnym!"
    exit 0;
fi

last_modified_dir=`ssh $_user@$_host "cd ~/$path_update; ls -t1d */ | sed 's/.$//' | grep '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}' | head -1" 2> /dev/null`

if [[ -z $last_modified_dir ]]; then
    echo "Nie znaleziono poprzednich backupów w zadanej ścieżce!"
    echo "Brak wzorca do sprawdzenia czasu ostatniej kopii zapasowej!"
    echo "Aby wykonać zwykły backup proszę wywołać skrypt z opcją -b"
    exit 0;
fi

echo "Pobieram datę"
last_date=`ssh $_user@$_host "cd ~/$path_update; date -r $last_modified_dir +%Y%m%d%H%M%S"`

h_file=`cat $list`
`touch /tmp/.backup_update.lst`

i=0
echo "Wyszkuję pliki przeznaczone do skopiowania"
for line in $h_file; do
    current_date=`date -r $line +%Y%m%d%H%M%S`
    if [[ $current_date > $last_date ]]; then
        echo $line >> /tmp/.backup_update.lst
        i=$((i+1))
    fi
done

if [[ i -lt 1 ]]; then
    echo "Nie znaleziono nowszych plików!"
    exit 0;
fi

h_update=`cat /tmp/.backup_update.lst`
echo "#----------------------------#"
echo " Lista plików do skopiowania: "
echo ""
cat /tmp/.backup_update.lst
echo "#----------------------------#"

echo "Tworzę strukturę katalogów"
`ssh $_user@$_host "mkdir -p ~/$path_update/$dir_name"`
echo "Transferuję pliki..."
`scp -r $h_update $_user@$_host:~/$path_update/$dir_name/`

`rm /tmp/.backup_update.lst`
`unset h_update`
exit 0;
}

function f_backup
{
f_check_if_list_exists
f_check_list_validity

h_file=`cat $list`
dir_name=`date +%F-%H-%M-%S`

echo "Nawiązuję połączenie z $_host"
`ssh $_user@$_host "mkdir -p ~/$path_backup/$dir_name"`

echo "<< Połączenie nawiązane! >>"
echo "Transferuję pliki..."
`scp -r $h_file $_user@$_host:~/$path_backup/$dir_name/`
echo "Kopiowanie zakończone sukcesem!"
}

function f_remove_list
{
`rm $list`
echo "Usuwam plik backup.lst"
}

function f_create_list
{
`touch $list`
echo "Tworzę plik backup.lst"
}

function f_path_remove
{
f_check_if_list_exists

if grep -Fxq "$path_remove" $list; then
    `sed -i "\:$path_remove:d" $list`

else
    echo "Scieżka "$path_remove" nie istnieje w pliku backup.lst!"
fi

if [[ -s $list ]]; then
    echo "Plik backup.lst wciąż posiada elementy. Nie usuwam pliku."
else
    echo "Plik backup.lst jest pusty. Usuwam."
    f_remove_list
fi
}

function f_path_add
{
if [[ ! -f $list ]]; then
    echo "Plik backup.lst nie istnieje. Tworzę plik..."
    f_create_list
fi

if grep -Fxq "$path_add" $list; then
    echo "Ścieżka "$path_add" istnieje już w pliku backup.lst!"
else
    if [[ -d "$path_add" || -f "$path_add" ]]; then
        echo $path_add >> $list
    else
        echo "Wskazany plik lub katalog nie istnieje!"
    fi
    
fi
}

while getopts ":phb:u:r:a:" opt; do
    case ${opt} in
        p)
        f_print_lst
        ;;
        h)
        f_help
        ;;
        a)
        path_add=`realpath $OPTARG`
        run_add=1
        ;;
        r)
        path_remove=`realpath $OPTARG`
        run_remove=1
        ;;
        b)
        path_backup=$OPTARG
        run_backup=1
        ;;
        u)
        path_update=$OPTARG
        run_update=1
        ;;
        \?) 
        echo "Nieistniejąca opcja: -"$OPTARG"" >&2
        echo "Aby wyświetlić pomoc proszę uruchomić skrypt z opcją: -h"
        exit 1
        ;;
        :) 
        echo "Opcja -"$OPTARG" wymaga podania argumentu." >&2
        exit 1
        ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Użycie: backup.sh -opcja"
    echo "Aby wyświetlić pomoc proszę uruchomić skrypt z argumentem -h"
    exit 1
fi

if [[ $run_add -eq 1 ]]; then
    f_path_add
fi
    
if [[ $run_remove -eq 1 ]]; then
    f_path_remove
fi

if [[ $run_backup -eq 1 ]]; then
    f_backup
fi

if [[ $run_update -eq 1 ]]; then
    f_update
fi
