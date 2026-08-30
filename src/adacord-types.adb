with Ada.Strings;
with Ada.Strings.Fixed;

package body Adacord.Types is

   use type Interfaces.Unsigned_64;

   function Parse_Snowflake (Value : String) return Snowflake is
      Result : Interfaces.Unsigned_64 := 0;
      Digit  : Interfaces.Unsigned_64;
   begin
      if Value'Length = 0 then
         raise Adacord.Invalid_Event with "empty snowflake";
      end if;

      if Value'Length > 1 and then Value (Value'First) = '0' then
         raise Adacord.Invalid_Event with
           "snowflake has a leading zero";
      end if;

      for Character_Value of Value loop
         if Character_Value not in '0' .. '9' then
            raise Adacord.Invalid_Event with
              "snowflake is not an unsigned decimal integer";
         end if;

         Digit := Interfaces.Unsigned_64
           (Character'Pos (Character_Value) - Character'Pos ('0'));

         if Result > (Interfaces.Unsigned_64'Last - Digit) / 10 then
            raise Adacord.Invalid_Event with "snowflake is out of range";
         end if;

         Result := Result * 10 + Digit;
      end loop;

      if Result = 0 then
         raise Adacord.Invalid_Event with "snowflake must be positive";
      end if;

      return Snowflake (Result);
   end Parse_Snowflake;

   function Is_Valid (Value : String) return Boolean is
   begin
      declare
         Parsed : constant Snowflake := Parse_Snowflake (Value);
         pragma Unreferenced (Parsed);
      begin
         return True;
      end;
   exception
      when Adacord.Invalid_Event =>
         return False;
   end Is_Valid;

   function Image (Value : Snowflake) return String is
   begin
      return Ada.Strings.Fixed.Trim
        (Interfaces.Unsigned_64'Image
           (Interfaces.Unsigned_64 (Value)),
         Ada.Strings.Both);
   end Image;

   function To_Unsigned_64
     (Value : Snowflake) return Interfaces.Unsigned_64 is
   begin
      return Interfaces.Unsigned_64 (Value);
   end To_Unsigned_64;

   function Length (List : Snowflake_List) return Natural is
   begin
      return Natural (List.Values.Length);
   end Length;

   function Element
     (List  : Snowflake_List;
      Index : Positive) return Snowflake is
   begin
      return Snowflake_Vectors.Element (List.Values, Index);
   end Element;

   procedure Append
     (List  : in out Snowflake_List;
      Value : Snowflake) is
   begin
      Snowflake_Vectors.Append (List.Values, Value);
   end Append;

end Adacord.Types;
