#!/bin/bash
generateExtraDappnodePackages() {
    if [[ -n "${EXTRA_PKGS}" ]]; then
        OUTFILE="extra-pkgs.json"
        echo "" > $OUTFILE
        printf "[\n" >> $OUTFILE
        IFS=',' read -r -a pkgs <<< "$EXTRA_PKGS"
        for pkg in "${pkgs[@]}"
        do
            mapfile -t filelines < /usr/src/app/iso/scripts/extra_dappnode_pkgs/"$pkg"
            {
                printf "\t{\n"
                printf "\t\t\"title\": \"%s\",\n" "${filelines[0]}" 
                printf "\t\t\"ipfs\": \"%s\",\n" "${filelines[1]}" 
                printf "\t\t\"description\": \"%s\",\n" "${filelines[2]}" 
                printf "\t\t\"needsUserInput\": \"%s\"\n" "${filelines[3]}" 
                printf "\t},\n"
            } >> $OUTFILE
        done
        sed -i '$ d' $OUTFILE
        printf "\t}\n]" >> $OUTFILE
        mv $OUTFILE /usr/src/app/dappnode/DNCORE/extra_pkgs.json
    fi
}
generateExtraDappnodePackages