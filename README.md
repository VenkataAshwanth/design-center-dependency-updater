# raml-dependency-updater 🚀

This utility automates the process of updating RAML fragment dependencies in MuleSoft Design Center projects. It simplifies dependency management by identifying outdated references and updating them efficiently.

## Target Audience
The RAML Dependency Updater Utility is designed for:
- **MuleSoft Developers** managing multiple Design Center projects with RAML dependencies.
- **Integration Architects** who aim to maintain consistency across MuleSoft environments.
- **C4E** Team responsible for ensuring dependencies are up to date.

This utility is ideal for teams working in complex MuleSoft environments where managing multiple dependencies efficiently is crucial.

## Problem Statement
Manually updating RAML fragment dependencies across multiple MuleSoft Design Center projects is a tedious and error-prone process. As projects grow, ensuring all dependencies are consistently updated becomes increasingly challenging.
Key issues faced during manual updates include:
- **Time-Consuming Process:** Manually locating and updating dependencies in multiple projects.
- **Risk of Errors:** Increased chances of missing critical updates or introducing version mismatches.
- **Inconsistent Dependencies:** Dependencies may remain outdated in some projects, causing runtime issues or unexpected behavior.

## Scope
This utility helps with:
- Updating RAML fragment dependencies in MuleSoft Design Center projects
- Managing multiple organizations and projects through a YAML configuration file
- Ensuring consistency and reducing manual errors in dependency updates

## 📌 Prerequisites
⚠️ **This script is designed to run only with Bash and is not compatible with standard Shell.**

Before running the utility, ensure the following:
- **Bash Shell** is available (e.g., `bash`).
- **Connected App Credentials** with all **Design Center** scopes assigned.
- **jq parser** and **YAML parser** are installed. If not present, you can install them with the following commands:

- **jq parser** (for JSON processing):
  ```bash
  sudo apt-get install jq  # Ubuntu/Debian
  brew install jq          # macOS
  ```

- **YAML parser** (like `yq` for YAML processing):
  ```bash
  sudo snap install yq     # Ubuntu/Debian
  brew install yq          # macOS
  ```

## 🚀 How to Run the Utility
1. Prepare your **YAML configuration file** (e.g., `dependency-config.yaml`). Include the projects and their respective dependencies that you want to update.
2. Ensure the `update-raml-dependencies.sh` script is executable by modifying its permissions:
    ```bash
   chmod +x update-raml-dependencies.sh
   ```
4. Run the script with the following command:  
   ```bash
   ./update-raml-dependencies.sh dependency-config.yaml
   ```
3. Review the logs for details on updated dependencies.

## 📄 Sample YAML Configuration
```yaml
organizations:
  - org_id: << ORG_ID >>
    client_id: << CLIENT_ID >>
    client_secret: << CLIENT_SECRET >>
    projects:
      - <<DESIGN CENTER PROJECT NAME>>:
          - <DEPENDENCY ID>
          - <DEPENDENCY ID>
```

## 📌 Unsupported Features
This utility does not:
- Create new Design Center projects or dependencies
- Validate RAML syntax or structure
- Manage MuleSoft runtime updates or version changes

## 🤝 Contributing
Contributions are welcome! Please submit issues and pull requests to improve the utility.

