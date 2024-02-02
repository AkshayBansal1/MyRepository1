$DHCP_Servers = "dl-dhcpp701.mdgapp.net","dl-dhcpp801.mdgapp.net";
$DHCP_Scope_Stats_All=@();
Foreach ($DHCP_Server in $DHCP_Servers){ ### Going through the DHCP servers that were returned one at a time to pull statistics
    $DHCP_Scopes = Get-DhcpServerv4Scope -ComputerName $DHCP_Server | Select-Object  ScopeId, Name, SubnetMask, StartRange, EndRange, LeaseDuration, State ### Getting all the dhcp scopes for the given server
    Foreach ($DHCP_Scope in $DHCP_Scopes){ ### Going through the scopes returned in a given server
        $DHCP_Scope_Stats = Get-DhcpServerv4ScopeStatistics -ComputerName $DHCP_Server -ScopeId $DHCP_Scope.ScopeId | Select-Object @{n='PSComputerName';e={$DHCP_Server}}, ScopeId, Free, InUse, Reserved, PercentageInUse ### Gathering the scope stats
#$DHCP_Scope_Stats = Get-DhcpServerv4ScopeStatistics -ComputerName $DHCP_Server -ScopeId $DHCP_Scope.ScopeId | Select-Object *
$DHCP_Scope_Stats_All+=$DHCP_Scope_Stats
    }
}
$DHCP_Scope_Stats_All | FT -autosize