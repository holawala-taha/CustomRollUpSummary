/**
 * @description : This class calculates the roll ups from the child objects.
 *                  use this when
 *                  1. The number of roll up fields are reached on the parent object
 *                  2. You need to establish a roll up field in a lookup relationship
 *
 * Custom Metadata type: Opportunity_Roll_Up_Calculation__mdt
 *                  Use this custom metadata to configure the roll ups
 *
 * @Author: tholawala@salesforce.com
 */
public with sharing class CustomRollUpCalculator {


    /**
     * @description : Use this method to register a child object to enforce roll up calculations on the parent.
     *                  Use this method in the After Insert, After Delete, After Update, and After Undelete
     *
     * @param parentObjectAPIName
     * @param childRelationshipName
     * @param parentAPIName
     * @param childRecords
     * @param oldMap
     */
    public static void triggerCustomRollUpCalculations(String parentObjectAPIName, String childRelationshipName,
                                                        String parentAPIName,List<SObject> childRecords,Map<Id,SObject> oldMap){
        Set<Id> parentRecordIds = new Set<Id>();


        if(Trigger.isExecuting){
            if(!Trigger.isAfter)
                return;

            // Query the custom metadata records
            List<Custom_Roll_Up_Calculation__mdt> rollUpMetadata = queryRollUpMetadata(parentObjectAPIName,childRelationshipName);

            if(Trigger.isInsert || Trigger.isDelete || Trigger.isUndelete){
                for(SObject childRecord : childRecords){

                    for(Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord : rollUpMetadata){
                        if(isCriteriaSatisfied(childRecord,rollUpMetadataRecord)){
                            if(childRecord.get(parentAPIName) != null){
                                String parentIdString = String.valueOf(childRecord.get(parentAPIName));
                                parentRecordIds.add(Id.valueOf(parentIdString));
                            }
                        }
                    }
                }
            }else{

                // Gather child fields to query
                Set<String> childFields     = getChildFieldsToQuery(rollUpMetadata);

                for(SObject childRecord : childRecords){
                    for(String field : childFields){
                        String childValueNew    = String.valueOf(childRecord.get(field));
                        String childValueOld    = String.valueOf(oldMap.get(childRecord.Id).get(field));
                        if(childValueNew != childValueOld) {
                            String parentIdString = String.valueOf(childRecord.get(parentAPIName));
                            parentRecordIds.add(Id.valueOf(parentIdString));
                        }
                    }
                }

            }
        }else{
            for(SObject childRecord : childRecords){
                if(childRecord.get(parentAPIName) != null){
                    String parentIdString = String.valueOf(childRecord.get(parentAPIName));
                    parentRecordIds.add(Id.valueOf(parentIdString));
                }
            }
        }

        if(parentRecordIds.size() > 0) {
            calculateRollUps(parentObjectAPIName,childRelationshipName,parentRecordIds);
        }
    }

    /**
     * @Description: This method calculates the Custom Roll Up fields based on the custom metadata configurations.
     *
     * @param parentObjectAPIName
     * @param childRelationshipName
     * @param parentRecordIds
     */
    public static void calculateRollUps(String parentObjectAPIName, String childRelationshipName, Set<Id> parentRecordIds){
        // Query the custom metadata records
        List<Custom_Roll_Up_Calculation__mdt> rollUpMetadata = queryRollUpMetadata(parentObjectAPIName,childRelationshipName);

        // Gather parent fields to query
        Set<String> parentFields    = getParentFieldsToQuery(rollUpMetadata);

        // Gather child fields to query
        Set<String> childFields     = getChildFieldsToQuery(rollUpMetadata);

        // Generate the Query
        List<SObject> records = buildQuery(parentObjectAPIName,childRelationshipName,parentRecordIds,parentFields,childFields);
        System.debug('Records size ' + records.size());

        // Perform roll ups
        for(Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord : rollUpMetadata){
            performRollUp(records,rollUpMetadataRecord,childRelationshipName);
        }

        update records;
    }

    public static List<Custom_Roll_Up_Calculation__mdt> queryRollUpMetadata(String parentObjectAPIName, String childRelationshipName){
        List<Custom_Roll_Up_Calculation__mdt> rollUpMetadata = [SELECT Id,Child_Object_Field_API_Name__c,
                                                                        Child_Relationship_API_Name__c,
                                                                        Operation_Type__c,
                                                                        Parent_Object_API_Name__c,
                                                                        Parent_Object_Field_API_Name__c,
                                                                        (SELECT Field_Name__c,Operator__c,value__c
                                                                            FROM Custom_Roll_Up_Calculation_Criterias__r)
                                                                    FROM Custom_Roll_Up_Calculation__mdt
                                                                    WHERE Parent_Object_API_Name__c =: parentObjectAPIName
                                                                        AND Child_Relationship_API_Name__c =: childRelationshipName ];

        return rollUpMetadata;
    }

    public static Set<String> getParentFieldsToQuery(List<Custom_Roll_Up_Calculation__mdt> rollUpMetadata){
        Set<String> parentFieldsToQuery = new Set<String>();

        for(Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord : rollUpMetadata){
            parentFieldsToQuery.add(rollUpMetadataRecord.Parent_Object_Field_API_Name__c);
        }

        return parentFieldsToQuery;
    }

    public static Set<String> getChildFieldsToQuery(List<Custom_Roll_Up_Calculation__mdt> rollUpMetadata){
        Set<String> childFieldsToQuery = new Set<String>();

        for(Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord : rollUpMetadata){
            childFieldsToQuery.add(rollUpMetadataRecord.Child_Object_Field_API_Name__c);

            for(Custom_Roll_Up_Calculation_Criteria__mdt criteria : rollUpMetadataRecord.Custom_Roll_Up_Calculation_Criterias__r)
                childFieldsToQuery.add(criteria.Field_Name__c);
        }

        return childFieldsToQuery;
    }

    public static List<SObject> buildQuery(String parentObjectAPIName, String childRelationshipName,Set<Id> parentRecordIds,
                                            Set<String> parentFields,Set<String> childFields){
        String query = 'SELECT Id';

        // Add parent fields
        for(String parentField : parentFields){
            query += ',' + parentField;
        }

        // Add child relationship fields
        query += ', (SELECT Id';
        for(String childField : childFields){
            query += ',' + childField;
        }

        // Add child relationship name
        query += ' FROM ' + childRelationshipName + ')';

        // Add parent object name and coniditions
        query += ' FROM ' + parentObjectAPIName + ' WHERE Id in : parentRecordIds';

        System.debug('Custom Roll Up Query -->' + query);

        return Database.query(query);
    }

    public static void performRollUp(List<SObject> records,Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord,
                                    String childRelationshipName){
        for(SObject record : records){
            record.put(rollUpMetadataRecord.Parent_Object_Field_API_Name__c,0);

            for(SObject childRecord : record.getSObjects(childRelationshipName)){
                 if(!isCriteriaSatisfied(childRecord,rollUpMetadataRecord))
                     continue;

                 if(rollUpMetadataRecord.Operation_Type__c == 'SUM'){
                     Decimal currentValue   = Decimal.valueOf(String.valueOf(record.get(rollUpMetadataRecord.Parent_Object_Field_API_Name__c)));
                     Decimal newValue       = Decimal.valueOf(String.valueOf(childRecord.get(rollUpMetadataRecord.Child_Object_Field_API_Name__c)));
                     record.put(rollUpMetadataRecord.Parent_Object_Field_API_Name__c,currentValue + newValue);
                 }else if(rollUpMetadataRecord.Operation_Type__c == 'COUNT'){
                     Integer currentValue   = Integer.valueOf(String.valueOf(record.get(rollUpMetadataRecord.Parent_Object_Field_API_Name__c)));
                     record.put(rollUpMetadataRecord.Parent_Object_Field_API_Name__c,currentValue + 1);
                 }
            }
        }
    }

    /**
     * @description : This method checks whether the child record satisfies the criteria (Defined in custom metadata) or not
     *
     * @param childRecord
     * @param rollUpMetadataRecord
     *
     * @return
     */
    public static Boolean isCriteriaSatisfied(SObject childRecord,Custom_Roll_Up_Calculation__mdt rollUpMetadataRecord){
        if(rollUpMetadataRecord.Custom_Roll_Up_Calculation_Criterias__r.size() == 0)
            return true;

        Boolean isValid = true;
        for(Custom_Roll_Up_Calculation_Criteria__mdt criteria : rollUpMetadataRecord.Custom_Roll_Up_Calculation_Criterias__r){
            String fieldValue = String.valueOf(childRecord.get(criteria.Field_Name__c));
            if(criteria.operator__c == 'Equals'){
                if(isDecimal(fieldValue) && isDecimal(criteria.Value__c)){
                    if(Decimal.valueOf(fieldValue) != Decimal.valueOf(criteria.Value__c)){
                        return false;
                    }
                }else if(CustomRollUpCalculator.isBoolean(fieldValue) && CustomRollUpCalculator.isBoolean(criteria.Value__c)){
                    if(Boolean.valueOf(fieldValue) != Boolean.valueOf(criteria.Value__c)){
                        return false;
                    }
                }else {
                    System.debug('Inside 3rd block');
                    if (childRecord.get(criteria.Field_Name__c) != criteria.Value__c)
                        return false;
                }
            }else if(criteria.operator__c == 'Does not equals'){
                System.debug('Inside Does not Equals');
                if(isDecimal(fieldValue) && isDecimal(criteria.Value__c)){
                    if(Decimal.valueOf(fieldValue) == Decimal.valueOf(criteria.Value__c)){
                        return false;
                    }
                }else if(isBoolean(fieldValue) && isBoolean(criteria.Value__c)){
                    if(Boolean.valueOf(fieldValue) == Boolean.valueOf(criteria.Value__c)){
                        return false;
                    }
                }else {
                    if (childRecord.get(criteria.Field_Name__c) == criteria.Value__c)
                        return false;
                }
            }else if(criteria.operator__c == 'Greater than'){
                if(!isDecimal(fieldValue) || !isDecimal(criteria.Value__c))
                    return false;
                if(Decimal.valueOf(fieldValue) <= Decimal.valueOf(criteria.Value__c))
                    return false;
            }else if(criteria.operator__c == 'Greater than or Equal'){
                if(!isDecimal(fieldValue) || !isDecimal(criteria.Value__c))
                    return false;
                if(Decimal.valueOf(fieldValue) < Decimal.valueOf(criteria.Value__c))
                    return false;
            }
            else if(criteria.operator__c == 'Less than'){
                if(!isDecimal(fieldValue) || !isDecimal(criteria.Value__c))
                    return false;
                if(Decimal.valueOf(fieldValue) >= Decimal.valueOf(criteria.Value__c))
                    return false;
            }else if(criteria.operator__c == 'Less than or Equal'){
                if(!isDecimal(fieldValue) || !isDecimal(criteria.Value__c))
                    return false;
                if(Decimal.valueOf(fieldValue) > Decimal.valueOf(criteria.Value__c))
                    return false;
            }else if(criteria.operator__c == 'Is Null'){
                Boolean isNull = childRecord.get(criteria.Field_Name__c) == null ? true : false;
                if(isNull != Boolean.valueOf(criteria.Value__c))
                    return false;
            }
        }

        return isValid;
    }

    // Check if the given string is a decimal or not
    public static Boolean isDecimal(String str){
        try{
            Decimal num = Decimal.valueOf(str);
            return true;
        }catch(Exception e){
            System.debug('String is not a decimal ' + str);
            return false;
        }
    }

    // Check if the given string is a Boolean or not
    public static Boolean isBoolean(String str){
        if(String.isNotBlank(str) && (str == 'True' || str == 'false'))
            return true;

        System.debug('String is not a Boolean ' + str);
        return false;
    }

}
