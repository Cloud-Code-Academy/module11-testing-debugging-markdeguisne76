@isTest
private class LeadTriggerHandlerTest {

    @testSetup
    static void setupData() {
        // Create an Account and Contact to test conversion against
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact matchingContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane@example.com',
            AccountId = acc.Id
        );
        insert matchingContact;
    }

    @isTest
    static void testHandleTitleNormalization() {
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName='John', LastName='Smith', Company='ABC Inc', Title='vp'),
            new Lead(FirstName='Sara', LastName='Jones', Company='XYZ Corp', Title='Head of Department'),
            new Lead(FirstName='Mike', LastName='Brown', Company='Tech Ltd', Title='Exec Director'),
            new Lead(FirstName='Lucy', LastName='White', Company='Health Inc', Title='Deputy Assistant'),
            new Lead(FirstName='Tom', LastName='Grey', Company='Other Co', Title='Other')
        };
        insert leads;

        Test.startTest();
        LeadTriggerHandler.handleTitleNormalization(leads);
        Test.stopTest();

        System.assertEquals('Vice President', leads[0].Title, 'Expected "vp" to normalize to "Vice President"');
        System.assertEquals('Manager', leads[1].Title, 'Expected "Head of Department" to normalize to "Manager"');
        System.assertEquals('Executive', leads[2].Title, 'Expected "Exec Director" to normalize to "Executive"');
        System.assertEquals('Assistant', leads[3].Title, 'Expected "Deputy Assistant" to normalize to "Assistant"');
        System.assertEquals('Other', leads[4].Title, 'Expected unrelated title to remain unchanged');
    }

    @isTest
    static void testHandleAutoLeadScoring() {
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName='Jane', LastName='Tech', Company='Tech Inc', Email='tech@example.com', Phone='123456', LeadSource='Website', Industry='Technology'),
            new Lead(FirstName='John', LastName='NoPhone', Company='NoPhone Inc', Email='yes@example.com', LeadSource='Website', Industry='Other'),
            new Lead(FirstName='Bob', LastName='NoEmail', Company='NoEmail Co', Phone='999888', Industry='Technology'),
            new Lead(FirstName='Sue', LastName='Nothing', Company='Nothing LLC') // Should score 0
        };
        insert leads;

        Test.startTest();
        LeadTriggerHandler.handleAutoLeadScoring(leads);
        Test.stopTest();

        System.assertEquals(18, leads[0].Lead_Score__c, 'Expected full score: Website + Email (3) + Phone (5) + Technology Industry (10)');
        System.assertEquals(3, leads[1].Lead_Score__c, 'Expected partial score: Website + Email (3)');
        System.assertEquals(15, leads[2].Lead_Score__c, 'Expected partial score: Phone (5) + Technology Industry (10)');
        System.assertEquals(0, leads[3].Lead_Score__c, 'Expected zero score for lead missing all inputs');
    }

    @isTest
    static void testHandleLeadAutoConvert_Positive() {
        Lead toConvert = new Lead(
            FirstName = 'Jane',
            LastName = 'Smith',
            Company = 'Convert Co',
            Email = 'jane@example.com'
        );
        insert toConvert;

        Test.startTest();
        LeadTriggerHandler.handleLeadAutoConvert(new List<Lead>{ toConvert });
        Test.stopTest();

        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :toConvert.Id];
        System.assert(result.IsConverted, 'Expected lead to be converted when a single matching contact exists');
    }

    @isTest
    static void testHandleLeadAutoConvert_NoMatch() {
        Lead noMatch = new Lead(
            FirstName = 'No',
            LastName = 'Match',
            Company = 'CompanyX',
            Email = 'notfound@example.com'
        );
        insert noMatch;

        Test.startTest();
        LeadTriggerHandler.handleLeadAutoConvert(new List<Lead>{ noMatch });
        Test.stopTest();

        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :noMatch.Id];
        System.assert(!result.IsConverted, 'Expected lead to remain unconverted when no matching contact exists');
    }

    @isTest
    static void testHandleLeadAutoConvert_MultipleMatches() {
        // Add a second contact with same email
        Contact dupContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Other',
            Email = 'jane@example.com',
            AccountId = [SELECT Id FROM Account LIMIT 1].Id
        );
        insert dupContact;

        Lead ambiguous = new Lead(
            FirstName = 'Duplicate',
            LastName = 'Lead',
            Company = 'Ambiguous Co',
            Email = 'jane@example.com'
        );
        insert ambiguous;

        Test.startTest();
        LeadTriggerHandler.handleLeadAutoConvert(new List<Lead>{ ambiguous });
        Test.stopTest();

        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :ambiguous.Id];
        System.assert(!result.IsConverted, 'Expected lead to remain unconverted when multiple matching contacts exist');
    }

    @isTest
static void testHandleLeadAutoConvert_AlreadyConverted() {
    // Get the test Account and Contact
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id, AccountId, Email FROM Contact WHERE Email = 'jane@example.com' LIMIT 1];

    // Step 1: Create and insert an unconverted lead with matching email
    Lead leadToConvert = new Lead(
        FirstName = 'Converted',
        LastName = 'Lead',
        Company = 'CompanyZ',
        Email = contact.Email
    );
    insert leadToConvert;

    // Step 2: Convert it using Database.convertLead
    LeadStatus status = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];
    Database.LeadConvert lc = new Database.LeadConvert();
    lc.setLeadId(leadToConvert.Id);
    lc.setContactId(contact.Id);
    lc.setAccountId(contact.AccountId);
    lc.setConvertedStatus(status.MasterLabel);
    lc.setDoNotCreateOpportunity(true);

    Database.convertLead(lc);

    // Step 3: Re-query to ensure it's converted
    Lead convertedLead = [SELECT Id, IsConverted, Email FROM Lead WHERE Id = :leadToConvert.Id];
    System.assert(convertedLead.IsConverted, 'Lead should have been converted already');

    // Step 4: Call your handler again, ensure no error or recursion
    Test.startTest();
    LeadTriggerHandler.handleLeadAutoConvert(new List<Lead>{ convertedLead });
    Test.stopTest();

    // Final assert to ensure it's still converted and test didn't fail
    convertedLead = [SELECT Id, IsConverted FROM Lead WHERE Id = :leadToConvert.Id];
    System.assert(convertedLead.IsConverted, 'Expected already converted lead to stay converted without errors');
    }
}

