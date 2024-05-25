library(tidyverse)
library(tidyquant)
library(gt)
library(gtExtras)
library(ggplot2)
library(rvest)
#devtools::install_github("https://github.com/klarsen1/MarketMatching")
library(MarketMatching)

#Getting data for SAP stock
sap_stock = c("SAP") %>%
  tidyquant::tq_get(get = "stock.prices", from = "2022-01-01", to = "2024-05-23")

#Plotting and highlighting date of layoff
sap_stock %>%
  ggplot(aes(x = as.Date(date), y = adjusted)) +
  geom_line() +
  labs(title = "SAP Stock price", y = "Closing (adjusted) Price", x = "",subtitle = "Possible effect of layoffs on price") +
  theme_tq() +
  geom_vline(xintercept = c(as.Date("2024-01-23")),
             linetype=4, colour="black")

#Preparing data
sap_stock_data = sap_stock %>%
  select(date,adjusted)%>%
  rename(y=adjusted)

tail(sap_stock_data) %>%
  gt()

#Setting periods pre and post intervention (layoffs)
pre.period <- as.Date(c(("2022-01-03") ,("2024-01-23")))
post.period <- as.Date(c(("2024-01-24"),("2024-05-17")))

#Running Causal Inference without any additional parameters
impact <- CausalImpact(sap_stock_data, pre.period, post.period)

#Plotting effects
plot(impact, c("original", "pointwise")) +
  labs(title = "Causal Effect layoffs on SAP stock price - first try")+
  coord_cartesian(xlim = c(as.Date("2022-06-01"),
                           as.Date("2024-05-17"))) +
  scale_x_date(labels = scales::label_date(format = "%Y %b")) +
  theme_bw(base_family = "Bricolage Grotesque")

#Checking numerical effect and coefficients
impact

#Finiding out more software companies
url = "https://stockanalysis.com/stocks/industry/software-application/"
page = read_html(url)
software_stocks = page %>% html_elements(".symbol-table") %>% html_table() %>%   .[[1]]
software_stocks %>%
  head %>%
  gt()

#Getting data for the largest 100
stocks = unique(software_stocks$Symbol)[1:100] %>%
  tidyquant::tq_get(get = "stock.prices", from = "2022-01-03", to = "2024-05-23")

all_stock_data = stocks %>%
  select(symbol, date,adjusted) %>%
  filter(!is.na(adjusted))

#Identifying best matches to use as control groups
mm <- MarketMatching::best_matches(data=all_stock_data,
                                   id="symbol",
                                   markets_to_be_matched = c("SAP"),
                                   date_variable="date",
                                   matching_variable="adjusted",
                                   parallel=F,
                                   start_match_period="2022-01-03",
                                   end_match_period="2024-01-23",
                                   matches = 10
)

#The 5 best are:
mm$BestMatches %>%
  filter(symbol == "SAP") %>%
  select(BestControl,rank,RelativeDistance,Correlation,Correlation_of_logs) %>%
  left_join(software_stocks %>% select(Symbol ,`Company Name`,`Market Cap`,Revenue), by=c("BestControl"="Symbol")) %>%
  relocate(`Company Name`,.before=rank) %>%
  rename(Symbol = BestControl) %>%
  mutate(across(c(RelativeDistance,Correlation,Correlation_of_logs),round,3))
head(5) %>%
  gt()%>%
  gt_highlight_rows(
    rows = c(1:3),
    fill = "#ccd5ae",
    bold_target_only = TRUE
  )

#Preparing new data set with predictors
sap_and_covariates = all_stock_data %>%
  filter(symbol %in% c("SAP","PTC","DUOL","APPF")) %>%
  select(date,symbol,adjusted) %>%
  pivot_wider(values_from=adjusted,names_from=symbol) %>%
  rename(y=SAP,x1=PTC,x2=DUOL) %>% filter(!is.na(x2)) %>%
  select(date,y,x1,x2)

#Running new iteration of Causal Inference
impact_2 <- CausalImpact(sap_and_covariates, pre.period, post.period,
                         model.args = list(niter = 5000))
#Plotting effect
plot(impact_2, c("original", "pointwise")) +
  labs(title = "Causal Effect layoffs on SAP stock price")+
  coord_cartesian(xlim = c(as.Date("2022-01-01"),
                           as.Date("2024-05-17"))) +
  scale_x_date(labels = scales::label_date(format = "%Y %b")) +
  theme_bw(base_family = "Bricolage Grotesque")

#Checking numerical effect and coefficients
impact_2
