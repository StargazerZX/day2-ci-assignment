# Answering the questions in Part 1

### 1. Which events will trigger your CI, and why? 

Three different triggers are configured for this CI pipeline:
    - On push to `main`, **except for changes to markdown or document files**
    - On PRs targeting `main`
    - Manually via the **Actions** page with specific inputs
    - Automatically every Monday at 7:00 UTC

### 2. Which jobs will you create? Draw the job graph (which run in parallel, which wait for which). 
    - `test`
    - `package` *(runs after `test`)*
    - `verify` *(runs after `package`)*
    - `report` *(**always** runs after `package` in parallel with `verify`, **regardless of whether `package` passed or not**)

### 3. What is the artifact this pipeline produces?
    - A JUnit Report (`reports/junit.xml`)
    - A `dist/temperature-<version>.tar.gz` archive containing `temperature.py` and `README.md`

### 4. Is this pipeline CI, Continuous Delivery, or Continuous Deployment? Justify in one sentence. 

This is a CI pipeline. It merely validates and packages the code, it doesn't run it on any live environments.

### 5. What should happen to the package job when tests fail, and why is that what you want? 

The `package` job should be skipped if the tests fail, as it means the code fails to meet required business rules, so it is ultimately dead code, and we want to fail fast.