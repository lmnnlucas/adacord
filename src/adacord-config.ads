package Adacord.Config is

   --  Load NAME=VALUE entries from Path into the process environment.
   --  A missing file is ignored. Existing environment variables take
   --  precedence unless Override is True.
   procedure Load_Dotenv
     (Path     : String := ".env";
      Override : Boolean := False);

   --  Return a non-empty environment value. If it is not already present,
   --  first try to load it from Dotenv_Path.
   function Required_Value
     (Name        : String;
      Dotenv_Path : String := ".env") return String;

end Adacord.Config;
