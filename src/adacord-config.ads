package Adacord.Config is
   --  Load local dotenv settings while preserving existing environment values.
   --  Only explicit Override=True replaces environment values. No substitution
   --  or escape expansion is performed. Diagnostics do not include secret values.
   --  Loading modifies the process environment and should happen during startup.

   procedure Load_Dotenv
     (Path     : String := ".env";
      Override : Boolean := False);
   --  Read NAME=VALUE assignments into the process environment.
   --  Supports an optional UTF-8 BOM, whitespace, export prefixes, single/double
   --  quotes and comments. A # after whitespace starts an unquoted comment;
   --  inside a quoted value or unquoted word it remains literal. A missing file
   --  is ignored. An invalid line raises an error; earlier assignments remain.
   --  @param Path File to read, relative to the current working directory by default.
   --  @param Override Replace environment values when True; otherwise preserve them.
   --  @exception Adacord.Configuration_Error Invalid file contents or read failure.
   --  @exception Ada.Text_IO.Use_Error File cannot be opened for reading.

   function Required_Value
     (Name        : String;
      Dotenv_Path : String := ".env") return String;
   --  Read a required, nonempty environment setting.
   --  Load Dotenv_Path only if Name does not already exist in the environment.
   --  An explicitly empty environment setting is not replaced with a file value.
   --  @param Name Portable environment name: letters, digits and underscore,
   --  with a letter or underscore first.
   --  @param Dotenv_Path Optional source of settings when Name is missing.
   --  @return Nonempty setting value; do not log returned credentials.
   --  @exception Adacord.Configuration_Error Invalid name, missing/empty value,
   --  or invalid dotenv contents.
   --  @exception Ada.Text_IO.Use_Error Dotenv file cannot be opened for reading.

end Adacord.Config;
