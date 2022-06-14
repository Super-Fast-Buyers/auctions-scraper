# Selenium remote driver
remDr <- RSelenium::remoteDriver(
  remoteServerAddr = "localhost",
  port = 4445L,
  browserName = "chrome",
  extraCapabilities = list(
    chromeOptions = list(args = c(
      "--headless", 
      "--disable-gpu", 
      "--no-sandbox",
      # "--disable-extensions",
      "--disable-dev-shm-usage"))))
Sys.sleep(2)
