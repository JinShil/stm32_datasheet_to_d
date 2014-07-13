// Copyright © 2014 Michael V. Franklin
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

module main;

import std.ascii;
import std.array;
import std.stdio;
import std.xml;
import std.string;
import std.conv;
import std.typecons;
import std.uni;

import org.eclipse.swt.SWT;
import org.eclipse.swt.graphics.Font;
import org.eclipse.swt.graphics.FontData;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.MessageBox;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.layout.RowData;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.events.ModifyEvent;
import org.eclipse.swt.events.ModifyListener;

alias TextBox = org.eclipse.swt.widgets.Text.Text;
alias isAlpha = std.uni.isAlpha;

TextBox xmlTextBox;
TextBox registerTextBox;
TextBox bitFieldsTextBox;
TextBox mutabilityTextBox;
TextBox dTextBox;

class BitField
{
    string name;
    string description;
    Nullable!(uint) endBit;
    Nullable!(uint) startBit;
    string mutability;
}

class Register
{
    string name;
    string description;
    string resetValue;
    string access;
    string addressOffset;
}

string stripName(string name)
{
    for(int i = 0; i < name.count; i++)
    {
        auto c = name[i];
        if (!c.isAlpha() && !c.isNumber())
        {
            return name[0..i];
        }
    }

    return name;
}

bool isOnlyWhiteSpace(TextBox textBox)
{
    return textBox.getText().strip().count < 1;
}

void datasheetToXml()
{
    immutable string xmlNewLine = "\r\n";

    if (registerTextBox.isOnlyWhiteSpace()
        || bitFieldsTextBox.isOnlyWhiteSpace()
        || mutabilityTextBox.isOnlyWhiteSpace())
    {
        // return;
    }

    Register register = new Register();

    string[] registerLines = registerTextBox.getText().splitLines();

    string registerNameLine = registerLines[0];

    // register name
    size_t startIndex = registerNameLine.lastIndexOf('_') + 1;
    size_t endIndex = registerNameLine.lastIndexOf(')');
    register.name = registerNameLine[startIndex..endIndex].strip();

    // register description
    endIndex = registerNameLine.indexOf('(');
    register.description = registerNameLine[0..endIndex].strip();

    // register address offset
    register.addressOffset = registerLines[1].replace("Address offset:", "").strip();

    // register reset value
    register.resetValue = registerLines[2].replace("Reset value:", "").replace(" ", "")[0..10];
    
    // register access
    string registerAccessLine = registerLines[3];
    if (registerAccessLine.indexOf("word, half-word and byte access") >= 0)
    {
        register.access = "Byte_HalfWord_Word";
    }
    else if (registerAccessLine.indexOf("word access") >= 0)
    {
        register.access = "Word";
    }
    else
    {
        throw new Exception("Couldn't understand access");
    }

    string[] mutabilityStrings = mutabilityTextBox.getText().split(" ");

    BitField thisBitField;
    BitField[] bitFields;
    auto registersLines = bitFieldsTextBox.getText().splitLines();
    foreach(line; registersLines)
    {
        auto words = line.split(" ");

        // starting a new bitfield
        if (line[0..3] == "Bit")
        { 
            // Add bitfield to list, with mutability
            if (thisBitField !is null)
            {
                string mutability = mutabilityStrings[bitFields.count];
                thisBitField.mutability = mutability;
                bitFields ~= thisBitField;
            }

            thisBitField = new BitField();

            if (words.count >= 3 && words[2].strip.toLower() == "reserved")
            {
                continue;
            }

            if (words.count >= 2)
            {
                string word1 = words[1].strip();
                immutable string colon = ":";
                if (word1.indexOf(colon) >= 0)
                {
                    string[] bitRange = word1.split(colon);
                    thisBitField.endBit = to!(uint)(bitRange[0]);
                    thisBitField.startBit = to!(uint)(bitRange[1]);
                }
                else
                {
                    thisBitField.endBit = to!(uint)(word1);
                    thisBitField.startBit = thisBitField.endBit;
                }
            }

            if (words.count >= 3)
            {
                thisBitField.name = words[2].strip().stripName();

                foreach(word; words[3..$])
                {
                    thisBitField.description ~= word ~ " ";
                }
            }
        }
        else if (thisBitField !is null)
        {
            thisBitField.description ~= xmlNewLine ~ line;
        }
    }

    // Add bitfield to list, with mutability
    if (thisBitField !is null)
    {
        string mutability = mutabilityStrings[bitFields.count];
        thisBitField.mutability = mutability;
        bitFields ~= thisBitField;
    }

    auto doc = new Document(new Tag("Registers"));

    auto registerElement = new Element("Register");
    registerElement.tag.attr["Name"] = register.name;
    registerElement.tag.attr["Description"] = register.description;
    registerElement.tag.attr["ResetValue"] = register.resetValue;
    registerElement.tag.attr["Access"] = register.access;
    registerElement.tag.attr["AddressOffset"] = register.addressOffset;
    doc ~= registerElement;

    foreach(bitField; bitFields)
    {
        Element element;

        element = new Element("BitField");
        element.tag.attr["Name"] = bitField.name;
        element.tag.attr["Description"] = bitField.description;
        element.tag.attr["StartBit"] = to!(string)(bitField.startBit);
        element.tag.attr["EndBit"] = to!(string)(bitField.endBit);
        element.tag.attr["Mutability"] = bitField.mutability;

        registerElement ~= element;
    }

    xmlTextBox.setText(join(doc.pretty(3), newline));
}

class OnDatasheetChangedListener : ModifyListener
{
    public void modifyText(ModifyEvent e)
    {
        try
        {
            datasheetToXml();
        }
        catch(Throwable t)
        {
            xmlTextBox.setText(t.msg);
        }
    }
}

void xmlToD()
{
    auto parser = new DocumentParser(xmlTextBox.getText());

    auto code = appender!string;
    parser.onStartTag["Register"] = (ElementParser e)
    {
        code.put("/****************************************************************************************" ~ newline);
        code.put(" " ~ e.tag.attr["Description"] ~ newline);
        code.put("*/" ~ newline);
        code.put("final abstract class " ~ e.tag.attr["Name"] ~ ": Register!(" ~ e.tag.attr["AddressOffset"] ~ ", Access." ~ e.tag.attr["Access"] ~ ")" ~ newline);
        code.put("{" ~ newline);

        string tab = "    ";

        e.onStartTag["BitField"] = (ElementParser e)
        {
            if (e.tag.attr["Name"].toLower() != "reserved")
            {
                code.put(tab ~ "/************************************************************************************" ~ newline);
                code.put(tab ~ e.tag.attr["Description"].replace(newline, newline ~ tab) ~ newline);
                code.put(tab ~ "*/" ~ newline);
                code.put(tab ~ "alias " ~ e.tag.attr["Name"] ~ " = ");
                if (e.tag.attr["EndBit"] == e.tag.attr["StartBit"])
                {
                    code.put("Bit!(" ~ e.tag.attr["EndBit"] ~ ", Mutability." ~ e.tag.attr["Mutability"] ~ ");");
                }
                else
                {
                    code.put("BitField!(" ~ e.tag.attr["EndBit"] ~ ", " ~ e.tag.attr["StartBit"] ~ ", Mutability." ~ e.tag.attr["Mutability"] ~ ");");
                }
                code.put(newline);
                code.put(newline);
            }
        };

        e.onEndTag["Register"] = (in Element e)
        {
            code.put("}" ~ newline);
        };

        e.parse();
    };
    
    parser.parse();

    dTextBox.setText(code.data);
}

class OnXmlChangedListener : ModifyListener
{
    public void modifyText(ModifyEvent e)
    {
        try
        {
            xmlToD();
        }
        catch(Throwable t)
        {
            dTextBox.setText(t.msg);
        }
    }
}

void main ()
{
    auto display = new Display;
    auto shell = new Shell(display);
    shell.setLayout(new GridLayout(3, false));

    Font font = new Font(display, new FontData( "Courier New", 8, SWT.NORMAL ) );

    auto registerLabel = new Label(shell, SWT.NONE);
    registerLabel.setText("Register");
    registerLabel.setBackground(display.getSystemColor(SWT.COLOR_WIDGET_BACKGROUND));

    auto xmlLabel = new Label(shell, SWT.NONE);
    xmlLabel.setText("Xml");
    xmlLabel.setBackground(display.getSystemColor(SWT.COLOR_WIDGET_BACKGROUND));

    auto dLabel = new Label(shell, SWT.NONE);
    dLabel.setText("D Code");
    dLabel.setBackground(display.getSystemColor(SWT.COLOR_WIDGET_BACKGROUND));

    auto onDatasheetChangedListener = new OnDatasheetChangedListener();

    registerTextBox = new TextBox(shell, SWT.MULTI | SWT.BORDER | SWT.WRAP | SWT.V_SCROLL);
    auto registerTextBoxGridData = new GridData(GridData.FILL_HORIZONTAL);
    registerTextBoxGridData.heightHint = 150;
    registerTextBox.setLayoutData(registerTextBoxGridData);
    registerTextBox.addModifyListener(onDatasheetChangedListener);

    auto onXmlChangedListener = new OnXmlChangedListener();

    xmlTextBox = new TextBox(shell, SWT.MULTI | SWT.BORDER | SWT.V_SCROLL | SWT.H_SCROLL | SWT.READ_ONLY);
    auto xmlTextBoxGridData = new GridData(GridData.FILL_BOTH);
    xmlTextBoxGridData.verticalSpan = 5;
    xmlTextBox.setFont(font);
    xmlTextBox.setLayoutData(xmlTextBoxGridData);
    xmlTextBox.addModifyListener(onXmlChangedListener);

    dTextBox = new TextBox(shell, SWT.MULTI | SWT.BORDER | SWT.V_SCROLL | SWT.H_SCROLL | SWT.READ_ONLY);
    auto dTextBoxGridData = new GridData(GridData.FILL_BOTH);
    dTextBoxGridData.verticalSpan = 5;
    dTextBox.setFont(font);
    dTextBox.setLayoutData(xmlTextBoxGridData);

    auto bitFieldsLabel = new Label(shell, SWT.NONE);
    bitFieldsLabel.setText("BitFields");
    bitFieldsLabel.setBackground(display.getSystemColor(SWT.COLOR_WIDGET_BACKGROUND));

    bitFieldsTextBox = new TextBox(shell, SWT.MULTI | SWT.BORDER | SWT.WRAP | SWT.V_SCROLL);
    auto bitFieldsTextBoxGridData = new GridData(GridData.FILL_BOTH);
   // bitFieldsTextBoxGridData.grabExcessVerticalSpace = true;
    bitFieldsTextBox.setLayoutData(bitFieldsTextBoxGridData);
    bitFieldsTextBox.addModifyListener(onDatasheetChangedListener);

    auto mutabilityLabel = new Label(shell, SWT.NONE);
    mutabilityLabel.setText("Mutability");
    mutabilityLabel.setBackground(display.getSystemColor(SWT.COLOR_WIDGET_BACKGROUND));

    mutabilityTextBox = new TextBox(shell, SWT.MULTI | SWT.BORDER | SWT.WRAP | SWT.V_SCROLL);
    auto mutabilityTextBoxGridData = new GridData(GridData.FILL_HORIZONTAL);
    mutabilityTextBoxGridData.heightHint = 100;
    mutabilityTextBox.setLayoutData(mutabilityTextBoxGridData);
    mutabilityTextBox.addModifyListener(onDatasheetChangedListener);

    //text1.setText("text1");

    shell.open();

    while (!shell.isDisposed)
    {
        if (!display.readAndDispatch())
        {
            display.sleep();
        }
    }

    display.dispose();
}