with Ada.Environment_Variables;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Adacord.Config is

   use Ada.Strings;

   function Is_Letter (Value : Character) return Boolean is
     (Value in 'A' .. 'Z' or else Value in 'a' .. 'z');

   function Is_Digit (Value : Character) return Boolean is
     (Value in '0' .. '9');

   function Is_Valid_Name (Name : String) return Boolean;

   function Is_Valid_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0
        or else (Name (Name'First) /= '_'
                 and then not Is_Letter (Name (Name'First)))
      then
         return False;
      end if;

      for Character_Value of Name loop
         if Character_Value /= '_'
           and then not Is_Letter (Character_Value)
           and then not Is_Digit (Character_Value)
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Name;

   function Parsed_Value (Raw_Value : String) return String;

   function Parsed_Value (Raw_Value : String) return String is
      Value : constant String := Ada.Strings.Fixed.Trim (Raw_Value, Both);
   begin
      if Value'Length = 0 then
         return "";
      end if;

      if Value (Value'First) = '"' or else Value (Value'First) = ''' then
         if Value'Length < 2
           or else Value (Value'Last) /= Value (Value'First)
         then
            raise Constraint_Error with "unterminated quoted value";
         end if;

         return Value (Value'First + 1 .. Value'Last - 1);
      end if;

      return Value;
   end Parsed_Value;

   procedure Load_Dotenv
     (Path     : String := ".env";
      Override : Boolean := False)
   is
      File        : Ada.Text_IO.File_Type;
      Line_Number : Natural := 0;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when Ada.Text_IO.Name_Error =>
            return;
      end;

      begin
         while not Ada.Text_IO.End_Of_File (File) loop
            Line_Number := Line_Number + 1;

            declare
               Original : constant String := Ada.Text_IO.Get_Line (File);
               Trimmed  : constant String :=
                 Ada.Strings.Fixed.Trim (Original, Both);
            begin
               if Trimmed'Length > 0
                 and then Trimmed (Trimmed'First) /= '#'
               then
                  declare
                     Without_Export : constant String :=
                       (if Trimmed'Length > 7
                          and then Trimmed
                            (Trimmed'First .. Trimmed'First + 6) = "export "
                        then Ada.Strings.Fixed.Trim
                          (Trimmed
                             (Trimmed'First + 7 .. Trimmed'Last), Both)
                        else Trimmed);
                     Separator : constant Natural :=
                       Ada.Strings.Fixed.Index (Without_Export, "=");
                  begin
                     if Separator = 0 then
                        raise Constraint_Error with "missing '='";
                     end if;

                     declare
                        Name : constant String := Ada.Strings.Fixed.Trim
                          (Without_Export
                             (Without_Export'First .. Separator - 1), Both);
                        Value : constant String := Parsed_Value
                          (Without_Export
                             (Separator + 1 .. Without_Export'Last));
                     begin
                        if not Is_Valid_Name (Name) then
                           raise Constraint_Error with
                             "invalid environment variable name";
                        end if;

                        if Override
                          or else not Ada.Environment_Variables.Exists (Name)
                        then
                           Ada.Environment_Variables.Set (Name, Value);
                        end if;
                     end;
                  end;
               end if;
            end;
         end loop;

         Ada.Text_IO.Close (File);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;

            raise Adacord.Configuration_Error with
              "Invalid dotenv file " & Path
              & " at line" & Natural'Image (Line_Number);
      end;
   end Load_Dotenv;

   function Required_Value
     (Name        : String;
      Dotenv_Path : String := ".env") return String
   is
   begin
      if not Is_Valid_Name (Name) then
         raise Adacord.Configuration_Error with
           "Invalid environment variable name";
      end if;

      if not Ada.Environment_Variables.Exists (Name) then
         Load_Dotenv (Dotenv_Path);
      end if;

      if not Ada.Environment_Variables.Exists (Name)
        or else Ada.Environment_Variables.Value (Name)'Length = 0
      then
         raise Adacord.Configuration_Error with
           "Missing required setting " & Name
           & "; define it in the environment or in " & Dotenv_Path;
      end if;

      return Ada.Environment_Variables.Value (Name);
   end Required_Value;

end Adacord.Config;
