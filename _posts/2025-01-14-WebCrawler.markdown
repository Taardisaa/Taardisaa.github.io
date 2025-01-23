---
layout: post
title: "WebCrawler"
date: "2025-01-14 19:55:24 -0700"
categories: "Web"
---

## Install Instructions 

1. ~~``install selenium in python: `pip install selenium`~~
2. or maybe install undetected_chromedriver: `pip3 install undetected-chromedriver`
2. download chrome driver & chrome(test version): https://googlechromelabs.github.io/chrome-for-testing/
3. extract both in a location.
4. try with the following codes:
```python
import time
from selenium import webdriver
import undetected_chromedriver as uc

chrome_driver_path = r'E:\Workspace\CrawlerWorkspace\chromedriver-win64\chromedriver.exe'
browser_exec_path = r'E:\Workspace\CrawlerWorkspace\chrome-win64\chrome.exe'
options = uc.ChromeOptions()

options.add_argument(f"--window-size=1366,768")
options.add_argument(f'--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.182 Safari/537.36')
options.add_argument('--disable-blink-features=AutomationControlled')
options.add_argument("--disable-extensions")
options.add_argument("--proxy-server='direct://'")
options.add_argument("--proxy-bypass-list=*")
options.add_argument('--ignore-certificate-errors')
options.add_argument("--password-store=basic")
# options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--disable-extensions")
options.add_argument("--enable-automation")
options.add_argument("--disable-browser-side-navigation")
options.add_argument("--disable-web-security")
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--disable-infobars")
options.add_argument("--disable-gpu")
options.add_argument("--disable-setuid-sandbox")
options.add_argument("--disable-software-rasterizer")

# options.add_argument(f"--user-data-dir=PATH_TO_CHROME_PROFILE")
# options.add_argument('--proxy-server=IP_ADRESS:PORT')

try:
    driver = uc.Chrome(executable_path=chrome_driver_path, 
                       browser_executable_path=browser_exec_path, 
                       options=options)
    driver.get('https://www.google.com')
    time.sleep(5) # Let the user actually see something!
    # search_box = driver.find_element_by_name('q')
    # search_box.send_keys('ChromeDriver')
    # search_box.submit()
    time.sleep(5) # Let the user actually see something!
    driver.quit()
except Exception as e:
    print(e)
```

## Websites

1. ~~https://sites.google.com/chromium.org/driver/capabilities?authuser=0 (Java based selenium)~~
2. https://sites.google.com/chromium.org/driver/getting-started?authuser=0
3. https://www.selenium.dev/documentation/selenium_manager/
4. https://sites.google.com/chromium.org/driver/
5. https://selenium-python.readthedocs.io/installation.html
6. https://stackoverflow.com/questions/17361742/download-image-with-selenium-python