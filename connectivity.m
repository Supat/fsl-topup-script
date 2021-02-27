addpath("/Users/Sui/Documents/MATLAB/FSLNets");
addpath("/usr/local/fsl/etc/matlab")
addpath("/Users/Sui/Documents/MATLAB/libsvm/matlab");

ts = nets_load('group_post_rest', 0.8, 0);

ts_spectra = nets_spectra(ts);

Fnetmats = nets_netmats(ts,1,'corr');
Pnetmats = nets_netmats(ts,1,'ridgep',0.1);

size(Fnetmats)

[Znet_F,Mnet_F]=nets_groupmean(Fnetmats,0);
[Znet_P,Mnet_P]=nets_groupmean(Pnetmats,1);

nets_hierarchy(Znet_F,Znet_P,ts.DD);