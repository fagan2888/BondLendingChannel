cap log close 
clear all 
set scheme sol, permanently
graph set window fontface "Times New Roman"
set linesize 150

* Set directories 
display `"This is the path: `1'""'
global path "`1'"

display "${path}"
cd "$path"

*************************************************
** Variable definition and panel construction
*************************************************

	*** Variable defintion Worldscope ***
use ../../Int_Data/data/ws_bs_quarterly,clear
// Define outcome variables analogously to before
gen lev=tdebt/assets //total debt leverage
gen long_lev=ldebt/assets // long term debt leverage
gen mnet_lev=(tdebt-cash)/assets // manual net debt leverage
gen capexoverppnet=capex/ppnet
gen capexoverassets=capex/assets
gen lev_ST=sandcdebt/assets
gen fra_ST=sandcdebt/tdebt
gen cov_ratio=ebitda/intexp
gen profitability=ebitda/assets
gen DTI = tdebt/ebitda
gen NDTI = (tdebt-cash)/ebitda
gen CF = ebitda + ch_receivables - ch_inventories - ch_payables

sort isin date_q
drop if assets==.
duplicates tag isin date_q,gen(new)
by isin: egen tot_n = total(new)
drop if tot_n >0
drop new tot_n 
order isin date_q

tempfile bs_raw
save `bs_raw'

	* Create panel to fill the gaps
use ../../Int_Data/data/ws_bs_quarterly,clear
keep isin 
duplicates drop isin,force
gen date_q = qofd(date("01012000","DMY"))
format date_q %tq
gen dup = 80
expand dup
sort isin
by isin: gen n =_n-1
replace date_q = date_q + n
drop dup n
merge 1:1 isin date_q using `bs_raw'
drop if _merge==2
drop _merge
drop date



* Note that the shocks are defined backwards t-(t-1)
* Hence the changes in the balance sheet variables have to be defined forwards.
global bsitems "sales  cash assets ldebt tdebt tot_liabilities ppnet profitability "
foreach var of varlist $bsitems{
	forvalues i=1/8{
		bys isin: gen d`i'q_`var'=(ln(`var'[_n+`i'])-ln(`var'[_n]))*100
	}
}

	* Lagged growth
foreach var of varlist $bsitems{
		bys isin: gen l1q_`var'=ln(`var'[_n])-ln(`var'[_n-1])
		bys isin: gen l2q_`var'=ln(`var'[_n-1])-ln(`var'[_n-2])
		bys isin: gen l3q_`var'=ln(`var'[_n-2])-ln(`var'[_n-3])
}


* Create three lags of the dependent variable
sort isin date_q
foreach var in sales  cash assets ldebt tdebt tot_liabilities ppnet{
bys isin: gen L1`var'=`var'[_n-1]
bys isin: gen L2`var'=`var'[_n-2]
bys isin: gen L3`var'=`var'[_n-3]
}

tempfile bs_quarterly
save `bs_quarterly'

	*** Get GDP Data ***
import excel ../../Raw_Data/original/ECB_gdp_growth.xlsx,clear firstrow cellrange(A5)
gen date_q = quarterly(PeriodUnit,"YQ")
format date_q %tq
sort date_q
gen l1_gdp_growth = gdp_growth[_n-1]
gen l2_gdp_growth = gdp_growth[_n-2]
drop PeriodUnit
save ../../Int_Data/data/gdp_growth,replace

	*** Get Inflation Data ***
import excel ../../Raw_Data/original/ECB_hicp.xlsx,clear firstrow cellrange(A5)
gen date_m = monthly(PeriodUnit,"YM")
gen date_q = qofd(dofm(date_m))
format date_q %tq
bys date_q: gen nn=_n
keep if nn==3
drop PeriodUnit date_m nn
rename Percentagechange inflation_yoy
gen l1_inflation_yoy = inflation_yoy[_n-1]
save ../../Int_Data/data/inflation_yoy,replace

	*** Final Panel	***
use ../data/Default_quarterly_sample,clear
gen length = (end_date + 1 - start_date) 
gen date_q = start_date
expand length
sort isin 
by isin: gen n = _n-1
replace date_q = date_q + n
keep isin date_q
sort isin date_q
format date_q %tq 
/// 12,223 quarter isin observations

merge m:1 date_q using ../../Int_Data/data/shock_quarterly
drop if _merge==2
drop _merge

merge m:1 date_q using ../../Int_Data/data/Default_JKshock_quarterly
drop if _merge==2
drop _merge

merge m:1 date_q isin using `bs_quarterly'
gen d_sample = _merge!=2
gen d_merged = _merge==3
gen d_unmerged = _merge==1
drop _merge

merge m:1 date_q using ../../Int_Data/data/gdp_growth
drop if _merge==2
drop _merge

merge m:1 date_q using ../../Int_Data/data/inflation_yoy
drop if _merge==2
drop _merge

merge m:1 isin using ../data/Default_finalsample_Y
keep if _merge==3
drop _merge
sort isin date_q

save ../../Int_Data/data/Default_lp_q_balancesheet,replace

********************************************************************************

	***
use ../../Analysis/data/Firm_Return_WS_Bond_Duration_Data_Default_Sample,clear
drop tag_IY
egen tag_IY=tag(isin year) 
keep if tag_IY

global firmcontrols "size cash_oa profitability tangibility log_MB DTI cov_ratio"
keep isin year lev_mb_IQ q_lev_mb_IQ lev_IQ fra_mb_IQ $firmcontrols sic 
tempfile mlev
save `mlev'


use ../../Int_Data/data/Default_lp_q_balancesheet,clear
gen year = year(dofq(date_q))

merge m:1 year isin using `mlev'
drop _merge
sort isin date_q

keep if  date_q <= quarterly("2006q3","YQ") 

gen d2sic=int(sic/100)


/*
gen industry = 0
replace industry=1 if sic >=100 & sic < 1000
replace industry=2 if sic >=1000 & sic < 1500
replace industry=3 if sic >=1500 & sic < 1800
replace industry=4 if sic >=2000 & sic < 4000
replace industry=5 if sic >=4000 & sic < 5000
replace industry=6 if sic >=5000 & sic < 5200
replace industry=7 if sic >=5200 & sic < 6000
replace industry=8 if sic >=6000 & sic < 6800
replace industry=9 if sic >=7000 & sic < 9000
replace industry=10 if sic >=9100 & sic < 9730
replace d2sic =industry
*/

preserve
* Within industry and year market leverage tercile
	local timeunit "date_q"

	egen tag_FY = tag(isin `timeunit')
	keep if tag_FY == 1

	egen n_indyear_FYI = count(lev_mb_IQ) ,by(`timeunit' d2sic)
	tab n_indyear_FYI

	drop if n_indyear_FYI<3

	*  Terciles of bond debt per industry x year
	gen q_levmarketIQ_YI=.

	levelsof `timeunit', local(years)
	foreach y of local years {
		levelsof d2sic if `timeunit' == `y', local(inds)
		foreach industry of local inds {	
			display "Year: `y' and industry: `industry'"	
			xtile q_help = lev_mb_IQ if `timeunit' == `y' & d2sic == `industry' , nq(3)	
			replace q_levmarketIQ_YI=q_help if `timeunit' == `y' & d2sic == `industry'
			drop  q_help
		}
	}

	keep q_levmarketIQ_YI isin `timeunit'
	tempfile FY_withinInd_tercile
	save `FY_withinInd_tercile'
restore

merge m:1 isin `timeunit' using `FY_withinInd_tercile'
drop _merge

egen IQ_dummy = group(d2sic date_q)
*assets sales ppnet profitability tot_liabilities 
foreach var in assets sales ppnet profitability tot_liabilities  {
	forvalues i=1/8{
		quietly areg d`i'q_`var',absorb(IQ_dummy)
		predict d`i'q_`var'_res,residual
	}
}

save ../data/Default_lp_q_balancesheet_terciles,replace


********************************************************************************

use ../data/Default_lp_q_balancesheet_terciles,clear



*replace agg_shock_ois_q = agg_shock_JK_q_noinfo * 100
*keep if year > 2000 & date_q <= quarterly("2006q2","YQ") 
// account for the leads reaching until 2007q4

gen temp = 1
gen leads=_n-1
*sales ppnet profitability tot_liabilities
forvalues tercile = 1/3{
	* assets  sales  tot_liabilities
	foreach var in assets ppnet sales  tot_liabilities { 
	
	
	display "################# Process variable `var' ########################"
	
	gen coef_`var'_ter`tercile'=.
	gen se_`var'_ter`tercile'=.
	gen ciub_`var'_ter`tercile'=.
	gen cilb_`var'_ter`tercile'=.
	gen n_`var'_ter`tercile'=.

	replace coef_`var'_ter`tercile'=0 if leads==0
	replace ciub_`var'_ter`tercile'=0 if leads==0
	replace cilb_`var'_ter`tercile'=0 if leads==0

	display "################# This is tercile `tercile' ########################"
	
	forvalues i=1/8{
		
		*reghdfe d`i'q_`var'_res c.agg_shock_ois_q $firmcontrols l1q_assets l2q_assets l1_gdp_growth l1_inflation_yoy if  q_levmarketIQ_YI == `tercile', absorb(isin) cluster(date_q isin)
		* q_levmarketIQ_YI q_lev_mb_IQ
		areg d`i'q_`var'_res c.agg_shock_ois_q $firmcontrols l1_gdp_growth l2_gdp_growth l1_inflation_yoy  l1q_assets l2q_assets  if  q_lev_mb_IQ == `tercile' & d_sample ,absorb(isin) 
		
		capture replace coef_`var'_ter`tercile'=_b[agg_shock_ois_q] if leads==`i'
		capture replace se_`var'_ter`tercile'=_se[agg_shock_ois_q]  if leads==`i'
		replace ciub_`var'_ter`tercile'=coef_`var'_ter`tercile'+1.68*se_`var'_ter`tercile'  if leads==`i'
		replace cilb_`var'_ter`tercile'=coef_`var'_ter`tercile'-1.68*se_`var'_ter`tercile'  if leads==`i'
		
		replace n_`var'_ter`tercile'=e(N) if leads == `i'
		}
	}
}

twoway  (rarea cilb_ppnet_ter1 ciub_ppnet_ter1 leads if leads>=0 & leads<=6, sort  color(blue%10) lw(vvthin)) ///
(scatter coef_ppnet_ter1  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(blue))  ///
 (rarea cilb_ppnet_ter3 ciub_ppnet_ter3 leads if leads>=0 & leads<=6, sort  color(red%10) lw(vvthin)) ///
 (scatter coef_ppnet_ter3  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(red)), ///
ylabel(-2(0.5)2) yline(0,lp(dash) lc(gs10)) ///
legend(order( 2 "Low Bond Leverage" 4 "High Bond Leverage" 1 "CI Tercile Low"  3 "CI Tercile High"  )) ///
xtitle("Horizon (in quaters)",size(large)) ytitle("Change in NetPPE (in %)",size(large)) name(ppnet,replace)
graph export ../../Analysis/output/Default_LP_PPENetTerciles.pdf,replace

twoway  (rarea cilb_assets_ter1 ciub_assets_ter1 leads if leads>=0 & leads<=6, sort  color(blue%10) lw(vvthin))(scatter coef_assets_ter1  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(blue))   (rarea cilb_assets_ter3 ciub_assets_ter3 leads if leads>=0 & leads<=6, sort  color(red%10) lw(vvthin))(scatter coef_assets_ter3  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(red)) ,ylabel(-1(0.5)1) yline(0,lp(dash) lc(gs10)) legend(order( 2 "Low Market Leverage" 4 "High Market Leverage" 1 "CI Tercile Low"  3 "CI Tercile High"  )) xtitle("Horizon (in quaters)",size(large)) ytitle("Change in Assets (in %)",size(large)) name(assets,replace)
graph export ../../Analysis/output/Default_LP_AssetsTerciles.pdf,replace

twoway  (rarea cilb_tot_liabilities_ter1 ciub_tot_liabilities_ter1 leads if leads>=0 & leads<=6, sort  color(blue%10) lw(vvthin))(scatter coef_tot_liabilities_ter1  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(blue))   (rarea cilb_tot_liabilities_ter3 ciub_tot_liabilities_ter3 leads if leads>=0 & leads<=6, sort  color(red%10) lw(vvthin))(scatter coef_tot_liabilities_ter3  leads if leads>=0 & leads<=6,c( l) lp(solid) mc(red)) ,ylabel(-1(0.5)1) yline(0,lp(dash) lc(gs10)) legend(order( 2 "Low Bond Leverage" 4 "High Bond Leverage" 1 "CI Tercile Low"  3 "CI Tercile High"  )) xtitle("Horizon (in quaters)",size(large)) ytitle("Change in Total Liabilities (in %)",size(large)) name(liab,replace)
graph export ../../Analysis/output/Default_LP_LiabilityTerciles.pdf,replace



********************************************************************************

	*** Altavilla et al. shock
import excel using ../../Raw_Data/original/Dataset_EA-MPD.xlsx, clear sheet("Press Release Window") firstrow

gen date_m = mofd(date)
format date_m %tm

egen agg_shock_ois_m = total(OIS_1M),by(date_m)
egen tagm = tag(date_m)
keep if tagm==1
keep agg_shock_ois_m date_m
tempfile shock_monthly
save `shock_monthly'


use ../../Int_Data/data/Financial_Variables,replace
merge 1:1 date using ../../Int_Data/data/MergedCleaned_MarketData.dta
drop if _merge==2
drop _merge

merge m:1 date_mon using ../../Int_Data/data/ECB_interest_loan.dta
drop if _merge==2
drop _merge

collapse (mean) BBB_5Y AA_5Y BBB_spread_5yr AA_spread_5yr loan_rate,by(date_mon)

rename date_mon date_m
merge 1:1 date_m using `shock_monthly'
drop if _merge==2


// Define interest rate differential between bank and bond
gen rate_diff_BBB_5Y=loan_rate-BBB_5Y
gen rate_diff_AA_5Y=loan_rate-AA_5Y

// Create changes in the bank_rate for horizons up to one year
foreach var in rate_diff_BBB_5Y rate_diff_AA_5Y{
forvalues i=1/12{
gen LD`i'_`var'=`var'[_n+`i']-`var'[_n]
}
}

foreach var in rate_diff_BBB_5Y rate_diff_AA_5Y{
forvalues i=1/3{
gen L`i'_`var'=`var'[_n-`i']
}
}

gen year = year(dofm(date_m))
keep if year > 2000 & year < 2007
// account for the fact that we have 12 monthly leads. So this goes until 12/2007

replace agg_shock_ois_m =0 if agg_shock_ois_m==.
	
gen leads=_n-1
tsset date_m


foreach var in rate_diff_BBB_5Y rate_diff_AA_5Y{
	gen coef_`var'=.
	gen se_`var'=.
	gen ciub_`var'=.
	gen cilb_`var'=.
	*gen n_`var'=.

	replace coef_`var'=0 if leads==0
	replace ciub_`var'=0 if leads==0
	replace cilb_`var'=0 if leads==0

	forvalues i=1/12{
	*qui reg LD`i'_`var' agg_shock_ois_m L1_`var' L2_`var' L3_`var' if insample==1,r
	*qui reg LD`i'_`var' agg_shock_ois_m L1_`var' if insample==1,r
	// Try without lags
	*qui reg LD`i'_`var' agg_shock_ois_m if insample==1,r
	// With Newey-West standard errors
	newey LD`i'_`var' agg_shock_ois_m L1_`var' L2_`var' L3_`var' ,lag(12)
	capture replace coef_`var'=_b[agg_shock_ois_m] if leads==`i'
	capture replace se_`var'=_se[agg_shock_ois_m]  if leads==`i'
	replace ciub_`var'=coef_`var'+1.68*se_`var'  if leads==`i'
	replace cilb_`var'=coef_`var'-1.68*se_`var'  if leads==`i'
	*replace n_`var'=e(N) if leads == `i'
	}
}


twoway  (rarea ciub_rate_diff_BBB_5Y cilb_rate_diff_BBB_5Y leads if leads>=0 & leads<=12, sort  color(blue%10) lw(vvthin)) ///
(scatter coef_rate_diff_BBB_5Y   leads if leads>=0 & leads<=12,c( l) lp(solid) mc(blue)) ,   ///
yline(0,lp(dash) lc(gs10)) title("Diff. Bank Rate - BBB Bonds 5Y ") legend(off) xlabel(0(3)12) ///
legend(off) xtitle("Horizon (in month)",size(large))  name(DiffBBB5YSpread,replace)
graph export ../../Analysis/output/Default_LP_BankBBB5Y.pdf, replace

twoway  (rarea ciub_rate_diff_AA_5Y cilb_rate_diff_AA_5Y leads if leads>=0 & leads<=12, sort  color(blue%10) lw(vvthin)) ///
(scatter coef_rate_diff_AA_5Y   leads if leads>=0 & leads<=12,c( l) lp(solid) mc(blue)) ,   ///
yline(0,lp(dash) lc(gs10)) title("Diff. Bank Rate - AA Bonds 5Y ") legend(off) xlabel(0(3)12) ///
legend(off) xtitle("Horizon (in month)",size(large))  name(DiffAA5YSpread,replace)
graph export ../../Analysis/output/Default_LP_BankAA5Y.pdf, replace

