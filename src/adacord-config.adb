with Ada.Environment_Variables;
with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Adacord.Config is

   function Is_Whitespace (Value : Character) return Boolean is
     (Value = ' ' or else Value = Ada.Characters.Latin_1.HT
      or else Value = Ada.Characters.Latin_1.CR);

   function Trim (Value : String) return String is
      First : Integer := Value'First;
      Last  : Integer := Value'Last;
   begin
      while First <= Last and then Is_Whitespace (Value (First)) loop
         First := First + 1;
      end loop;
      while Last >= First and then Is_Whitespace (Value (Last)) loop
         Last := Last - 1;
      end loop;
      return Value (First .. Last);
   end Trim;

   function Without_BOM (Value : String) return String is
   begin
      if Value'Length >= 3
        and then Value (Value'First .. Value'First + 2) =
          Character'Val (16#EF#) & Character'Val (16#BB#)
          & Character'Val (16#BF#)
      then
         return Value (Value'First + 3 .. Value'Last);
      end if;
      return Value;
   end Without_BOM;

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
      Value : constant String := Trim (Raw_Value);
   begin
      if Value'Length = 0 then
         return "";
      end if;

      if Value (Value'First) = '"' or else Value (Value'First) = ''' then
         for Index in Value'First + 1 .. Value'Last loop
            if Value (Index) = Value (Value'First) then
               declare
                  Tail : constant String :=
                    Trim (Value (Index + 1 .. Value'Last));
               begin
                  if Tail'Length > 0 and then Tail (Tail'First) /= '#' then
                     raise Constraint_Error with "text after quoted value";
                  end if;
                  return Value (Value'First + 1 .. Index - 1);
               end;
            end if;
         end loop;
         raise Constraint_Error with "unterminated quoted value";
      end if;

      for Index in Value'Range loop
         if Value (Index) = '#'
           and then (Index = Value'First
                     or else Is_Whitespace (Value (Index - 1)))
         then
            return Trim (Value (Value'First .. Index - 1));
         end if;
      end loop;
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
                 Trim (if Line_Number = 1 then Without_BOM (Original)
                       else Original);
            begin
               if Trimmed'Length > 0
                 and then Trimmed (Trimmed'First) /= '#'
               then
                  declare
                     Without_Export : constant String :=
                       (if Trimmed'Length > 7
                          and then Trimmed
                            (Trimmed'First .. Trimmed'First + 5) = "export"
                          and then Is_Whitespace
                            (Trimmed (Trimmed'First + 6))
                        then Trim
                          (Trimmed
                             (Trimmed'First + 7 .. Trimmed'Last))
                        else Trimmed);
                     Separator : constant Natural :=
                       Ada.Strings.Fixed.Index (Without_Export, "=");
                  begin
                     if Separator = 0 then
                        raise Constraint_Error with "missing '='";
                     end if;

                     declare
                        Name : constant String := Trim
                          (Without_Export
                             (Without_Export'First .. Separator - 1));
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
