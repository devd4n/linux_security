#!/bin/bash
#
timestamp=$(date +%d-%m-%Y_%H-%M-%S)
echo "$timestamp | ufw rulebase update started | /home/srvadmin/scripts/auto_ufw_update.sh"

ALLOW_HOST_FILE=""          # Example: ALLOW_HOST_FILE="/home/srvadmin/scripts/current.ufw"
HISTORC_HOST_FILE=""        # Example: HISTORC_HOST_FILE="/home/scripts/before.ufw" 
DST_HOST=""                 # Example: DST_HOST="1.1.1.1" // must be IP-Adress
FIRST_UFW_DYN_RULE_NUMBER=2 # Rule Number where the dynamic updated rules can start

CLIENTS_MGMT=()             # Example: CLIENTS_MGMT=(my-dyndns-hostadress.de)
ALLOWED_PORTS_MGMT=()       # Example: ALLOWED_PORTS_MGMT=(22 443 8443)

CLIENTS_USER=()             # Example: CLIENTS_USER=(my-dyndns-hostadress.de, 1.2.3.0/24, 2.3.4.5)
ALLOWED_PORTS_USER=()       # Example: ALLOWED_PORTS_USER=(443 8443)


################## Write Custom Rule File #########################
rm -r $ALLOW_HOST_FILE

for nxt_src in "${CLIENTS_MGMT[@]}"
do
  if [[ "$nxt_src" =~ [a-zA-Z] ]]; then
      # Resolve Hostnames if needed (if no ip)
      nxt_src=$(nslookup $nxt_src | grep answer -A 3 | grep Address | sed -e "s/Address: //")
  fi
  for nxt_port in "${ALLOWED_PORTS_MGMT[@]}"
  do
    # Write File which represents the goal
    echo "$DST_HOST $nxt_port $nxt_src" >> $ALLOW_HOST_FILE
  done
done

for nxt_src in "${CLIENTS_USER[@]}"
do
  if [[ "$nxt_src" =~ [a-zA-Z] ]]; then
      # Resolve Hostnames if needed (if no ip)
      nxt_src=$(nslookup $nxt_src | grep answer -A 3 | grep Address | sed -e "s/Address: //")
  fi
  for nxt_port in "${ALLOWED_PORTS_USER[@]}"
  do
    # Write File which represents the goal
    echo "$DST_HOST $nxt_port $nxt_src" >> $ALLOW_HOST_FILE
  done
done

################## Override ufw config #########################

# Get Current Config from ufw
ufw status numbered | grep -A 1000000 "$FIRST_UFW_DYN_RULE_NUMBER]" | sed -e 's/\[.*\] //g' | sed -e 's/[ ]*ALLOW IN[ ]*/ /g' | sed -e 's/[ ]*$//g' | sed '/^[[:space:]]*$/d' > $HISTORC_HOST_FILE
# Get Line Numbers which differ from Current to new Config
diff=$(diff --unchanged-line-format="" --old-line-format="%5dnx" --new-line-format="%5dnx" $HISTORC_HOST_FILE $ALLOW_HOST_FILE | sed "s/x/\n/g" | sort -u)
max_rule_number_old=$(($(wc -l < $HISTORC_HOST_FILE)+${FIRST_UFW_DYN_RULE_NUMBER}-1))     # Number of Rules configured in ufw
# echo "diff:\n $diff"  # only for debugging
for number_of_line in $diff
do
  number_of_rule=$(($number_of_line+${FIRST_UFW_DYN_RULE_NUMBER}-1))
  echo "current | line-number: $number_of_line | rule-number: $number_of_rule"
  rule_line=$(sed "${number_of_line}q;d" $ALLOW_HOST_FILE)
  rule_data=($rule_line)
  if (( $number_of_rule < $max_rule_number_old )); then
    # Replace existing rules
    echo "replace: insert rule $number_of_rule allow from ${rule_data[2]} to ${rule_data[0]} port ${rule_data[1]}"
    ufw insert $number_of_rule allow from ${rule_data[2]} to ${rule_data[0]} port ${rule_data[1]}
    echo "delete: previous rule number: $number_of_rule"
    yes | ufw delete $(($number_of_rule+1))
  else
    # Add new Rule to bottom
    echo "new-to-bottom: insert rule $number_of_rule allow from ${rule_data[2]} to ${rule_data[0]} port ${rule_data[1]}"
    ufw allow from ${rule_data[2]} to ${rule_data[0]} port ${rule_data[1]}
  fi
done
echo "$timestamp | ufw rulebase updated"
