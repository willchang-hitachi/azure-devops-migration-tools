using System.Collections.Generic;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using MigrationTools.Shadows;
using MigrationTools.Tools;

namespace MigrationTools.ProcessorEnrichers.Tests
{
    [TestClass()]
    public class StringManipulatorToolTests
    {

        [TestMethod(), TestCategory("L1")]
        public void StringManipulatorTool_ConfigureTest()
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 10;
            options.Manipulators = new List<RegexStringManipulator>
                {
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = ".*",
                        Replacement = "Test",
                        Description = "Test"
                    }
                };

            var x = GetStringManipulatorTool(options);

            Assert.IsNotNull(x);
        }

        [TestMethod(), TestCategory("L1")]
        public void StringManipulatorTool_RegexTest()
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 10;
            options.Manipulators = new List<RegexStringManipulator>
                {
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = "Test",
                        Replacement = "Test 2",
                        Description = "Test"
                    }
                };

            var x = GetStringManipulatorTool(options);

            string value = "Test";
            string? newValue = x.ProcessString(value);

            Assert.AreEqual("Test 2", newValue);
        }

        [TestMethod(), TestCategory("L1")]
        public void StringManipulatorTool_LengthShorterThanMaxTest()
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 10;
            var x = GetStringManipulatorTool(options);

            string value = "Test";
            string? newValue = x.ProcessString(value);

            Assert.AreEqual(4, newValue.Length);
        }

        [TestMethod(), TestCategory("L1")]
        public void StringManipulatorTool_LengthLongerThanMaxTest()
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 10;
            var x = GetStringManipulatorTool(options);

            string value = "Test Test Test Test Test Test Test Test Test Test Test Test Test";
            string? newValue = x.ProcessString(value);

            Assert.AreEqual(10, newValue.Length);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow(null, null)]
        [DataRow("", "")]
        [DataRow("lorem", "lorem")]
        public void StringManipulatorTool_Disabled(string? value, string? expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = false;
            options.MaxStringLength = 15;
            options.Manipulators = new List<RegexStringManipulator>
                {
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = "(^.*$)",
                        Replacement = "$1 $1",
                        Description = "Test"
                    }
                };
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow(null, null)]
        [DataRow("", " ")]
        [DataRow("lorem", "lorem lorem")]
        [DataRow("lorem ipsum", "lorem ipsum lor")]
        public void StringManipulatorTool_Process(string? value, string? expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 15;
            options.Manipulators = new List<RegexStringManipulator>
                {
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = "(^.*$)",
                        Replacement = "$1 $1",
                        Description = "Test"
                    }
                };
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow(null, null)]
        [DataRow("", " 1 2")]
        [DataRow("lorem", "lorem 1 2")]
        public void StringManipulatorTool_MultipleManipulators(string? value, string? expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 15;
            options.Manipulators = new List<RegexStringManipulator>
                {
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = "(^.*$)",
                        Replacement = "$1 1",
                        Description = "Add 1"
                    },
                    new RegexStringManipulator
                    {
                        Enabled = true,
                        Pattern = "(^.*$)",
                        Replacement = "$1 2",
                        Description = "Add 2"
                    }
                };
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow("Hello", "Hello")]
        [DataRow("Héllo", "Héllo")]    // New behavior: accented chars preserved
        [DataRow("Привет", "Привет")]    // New behavior: Cyrillic chars preserved
        [DataRow("你好", "你好")]      // New behavior: Chinese chars preserved
        [DataRow("Café résumé", "Café résumé")]  // New behavior: accented chars preserved
        [DataRow("Test\u0001\u0002", "Test")]  // Control chars should be removed
        [DataRow("Line1\nLine2", "Line1\nLine2")]  // Newlines should be preserved
        [DataRow("Tab\tSeparated", "Tab\tSeparated")]  // Tabs should be preserved
        public void StringManipulatorTool_DefaultManipulator_UnicodeSupport(string value, string expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 1000;
            // No manipulators set - should use default
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow("Hello", "Hello")]
        [DataRow("Héllo", "Héllo")]    // Expected behavior: accented chars preserved
        [DataRow("Привет", "Привет")]    // Expected behavior: Cyrillic chars preserved
        [DataRow("你好", "你好")]      // Expected behavior: Chinese chars preserved
        [DataRow("Café résumé", "Café résumé")]  // Expected behavior: accented chars preserved
        [DataRow("Test\u0001\u0002", "Test")]  // Control chars should still be removed
        [DataRow("Line1\nLine2", "Line1\nLine2")]  // Newlines should be preserved
        [DataRow("Tab\tSeparated", "Tab\tSeparated")]  // Tabs should be preserved
        public void StringManipulatorTool_DefaultManipulator_ExpectedBehavior(string value, string expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 1000;
            // Use improved Unicode-supporting pattern
            options.Manipulators = new List<RegexStringManipulator>
            {
                new RegexStringManipulator
                {
                    Enabled = true,
                    Description = "Default: Removes control characters but preserves Unicode letters and symbols",
                    Pattern = @"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]+",
                    Replacement = ""
                }
            };
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        [TestMethod(), TestCategory("L1")]
        [DataRow("Hello 😀 World", "Hello  World")]           // Basic emoticons should be stripped (surrogate pairs)
        [DataRow("Test 🔥 Fire", "Test  Fire")]              // Fire emoji should be stripped (surrogate pairs)
        [DataRow("Code 💻 Work", "Code  Work")]              // Laptop emoji should be stripped (surrogate pairs)
        [DataRow("Heart ❤️ Love", "Heart ❤ Love")]           // Variation selector stripped, heart symbol preserved
        [DataRow("Flag 🇺🇸 Country", "Flag  Country")]        // Regional indicators stripped (surrogate pairs)
        [DataRow("Math ∑ Symbol", "Math ∑ Symbol")]           // Mathematical symbols preserved (not surrogate pairs)
        [DataRow("Arrow → Direction", "Arrow → Direction")]    // Arrows preserved (not surrogate pairs)
        [DataRow("Check ✓ Mark", "Check ✓ Mark")]             // Useful dingbats preserved (not surrogate pairs)
        [DataRow("Star ★ Rating", "Star ★ Rating")]           // Miscellaneous symbols preserved (not surrogate pairs)
        [DataRow("Café résumé", "Café résumé")]              // Regular Unicode letters preserved
        [DataRow("Test\u0001\u0002", "Test")]                // Control chars should be removed
        public void StringManipulatorTool_DefaultManipulator_EmojiStripping(string value, string expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 1000;
            // No manipulators set - should use default (which should strip emojis)
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        /// <summary>
        /// System.Description and System.History hold rich text, so the default manipulator has to
        /// clean the content without destroying the surrounding markup.
        /// </summary>
        [TestMethod(), TestCategory("L1")]
        [DataRow("<div>Hello</div>", "<div>Hello</div>")]                                  // Html markup preserved
        [DataRow("<div>Hello World</div>", "<div>Hello World</div>")]                // Control chars removed from inside markup
        [DataRow("<p>Ship it 😀</p>", "<p>Ship it </p>")]                        // Emoji stripped from inside markup
        [DataRow("<a href=\"http://x/y\">café</a>", "<a href=\"http://x/y\">café</a>")]    // Attributes and Unicode preserved
        [DataRow("## Heading\n\n- item", "## Heading\n\n- item")]                          // Markdown rich text preserved
        public void StringManipulatorTool_DefaultManipulator_RichTextFields(string value, string expected)
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 1000;
            // No manipulators set - should use default
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString(value);
            Assert.AreEqual(expected, newValue);
        }

        /// <summary>
        /// A configured manipulator has to apply to rich text content the same way it applies to
        /// single line string fields.
        /// </summary>
        [TestMethod(), TestCategory("L1")]
        public void StringManipulatorTool_CustomManipulator_AppliesToRichText()
        {
            var options = new StringManipulatorToolOptions();
            options.Enabled = true;
            options.MaxStringLength = 1000;
            options.Manipulators = new List<RegexStringManipulator>
            {
                new RegexStringManipulator
                {
                    Enabled = true,
                    Description = "Repoint embedded links at the target collection",
                    Pattern = "http://oldserver/",
                    Replacement = "https://dev.azure.com/newserver/"
                }
            };
            var x = GetStringManipulatorTool(options);

            string? newValue = x.ProcessString("<a href=\"http://oldserver/tfs/_workitems\">link</a>");

            Assert.AreEqual("<a href=\"https://dev.azure.com/newserver/tfs/_workitems\">link</a>", newValue);
        }

        private static StringManipulatorTool GetStringManipulatorTool(StringManipulatorToolOptions options)
        {
            var services = new ServiceCollection();
            services.AddMigrationToolServicesForUnitTests();
            services.AddSingleton<StringManipulatorTool>();
            services.Configure<StringManipulatorToolOptions>(o =>
            {
                o.Enabled = options.Enabled;
                o.MaxStringLength = options.MaxStringLength;
                o.Manipulators = options.Manipulators;
            });
            return services.BuildServiceProvider().GetService<StringManipulatorTool>();
        }
    }
}
